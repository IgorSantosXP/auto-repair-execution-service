require "rails_helper"

RSpec.describe Execution::UseCases::StartExecution do
  let(:uuid) { SecureRandom.uuid }

  def parts_for(*pairs)
    pairs.map { |id, quantity| { "part_id" => id, "name" => "Part #{id}", "quantity" => quantity } }
  end

  def outbox_events
    DynamoOutbox.pending.map { |item| Messaging::Envelope.parse(item["body"]) }
  end

  before do
    create_part(id: "oleo", stock: 10)
    create_part(id: "filtro", stock: 2)
  end

  context "when every part has stock" do
    let(:envelope) { start_envelope(uuid: uuid, parts: parts_for([ "oleo", 3 ], [ "filtro", 1 ])) }

    it "reserves the stock, queues the execution and writes the execution.queued outbox item" do
      result = described_class.call(envelope)

      expect(result).to be_success
      expect(stock_of("oleo")).to eq(7)
      expect(stock_of("filtro")).to eq(1)

      execution = Execution::Gateways::ExecutionRepository.find(uuid)
      expect(execution).to include("status" => "queued", "saga_id" => envelope.saga_id, "notes" => "Troca de óleo")
      expect(execution["timeline"].map { |t| t["status"] }).to eq([ "queued" ])

      events = outbox_events
      expect(events.map(&:type)).to eq([ "execution.queued" ])
      expect(events.first.payload).to eq("position" => 1)
      expect(events.first).to have_attributes(destination: "os", saga_id: envelope.saga_id, service_order_uuid: uuid)
    end

    it "records a reservation movement per part referencing the service order" do
      described_class.call(envelope)

      movement = Inventory::Gateways::StockMovementRepository.for_part("oleo").find { |m| m["movement_type"] == "reservation" }
      expect(movement).to include("quantity" => 3, "reference" => uuid)
    end

    it "computes the position from the queued executions" do
      queue_execution
      queue_execution

      expect(described_class.call(envelope).payload).to eq(position: 3)
    end

    it "emits the reserved metric" do
      expect(Telemetry).to receive(:stock_reservation).with(result: "reserved")
      described_class.call(envelope)
    end
  end

  it "aggregates repeated parts" do
    described_class.call(start_envelope(uuid: uuid, parts: parts_for([ "oleo", 2 ], [ "oleo", 3 ])))

    expect(stock_of("oleo")).to eq(5)
    expect(Execution::Gateways::ExecutionRepository.find(uuid)["parts"]).to eq([ { "part_id" => "oleo", "name" => "Part oleo", "quantity" => 5 } ])
  end

  it "queues executions without parts" do
    expect(described_class.call(start_envelope(uuid: uuid, parts: []))).to be_success
    expect(outbox_events.map(&:type)).to eq([ "execution.queued" ])
  end

  it "ignores parts with invalid quantity" do
    described_class.call(start_envelope(uuid: uuid, parts: parts_for([ "oleo", 0 ], [ "oleo", -1 ])))
    expect(stock_of("oleo")).to eq(10)
  end

  context "with insufficient stock" do
    let(:envelope) { start_envelope(uuid: uuid, parts: parts_for([ "oleo", 3 ], [ "filtro", 5 ])) }

    it "creates nothing, keeps the stock and publishes execution.failed" do
      result = described_class.call(envelope)

      expect(result).to be_failure
      expect(Execution::Gateways::ExecutionRepository.find(uuid)).to be_nil
      expect(stock_of("oleo")).to eq(10)
      expect(stock_of("filtro")).to eq(2)
      expect(Inventory::Gateways::StockMovementRepository.for_part("oleo").map { |m| m["movement_type"] }).to eq([ "inbound" ])

      event = outbox_events.sole
      expect(event.type).to eq("execution.failed")
      expect(event.payload["reason"]).to eq("insufficient_stock")
      expect(event.payload["details"]).to eq([ { "part_id" => "filtro", "name" => "Part filtro", "requested" => 5, "available" => 2 } ])
    end

    it "emits the insufficient_stock metric" do
      expect(Telemetry).to receive(:stock_reservation).with(result: "insufficient_stock", reason: "insufficient_stock")
      described_class.call(envelope)
    end
  end

  it "fails with unknown_part when a part does not exist" do
    described_class.call(start_envelope(uuid: uuid, parts: parts_for([ "oleo", 1 ], [ "ghost", 1 ])))

    event = outbox_events.sole
    expect(event.payload["reason"]).to eq("unknown_part")
    expect(event.payload["details"]).to eq([ { "part_id" => "ghost", "name" => "Part ghost", "requested" => 1, "available" => 0 } ])
    expect(stock_of("oleo")).to eq(10)
  end

  it "treats inactive parts as unknown" do
    Inventory::UseCases::DeactivatePart.call(part_id: "oleo")
    described_class.call(start_envelope(uuid: uuid, parts: parts_for([ "oleo", 1 ])))

    expect(outbox_events.sole.payload["reason"]).to eq("unknown_part")
  end

  it "is a no-op when the same service order is started twice" do
    envelope = start_envelope(uuid: uuid, parts: parts_for([ "oleo", 3 ]))
    described_class.call(envelope)
    result = described_class.call(start_envelope(uuid: uuid, parts: parts_for([ "oleo", 3 ])))

    expect(result).to be_success
    expect(stock_of("oleo")).to eq(7)
    expect(outbox_events.map(&:type)).to eq([ "execution.queued" ])
  end

  it "re-raises cancellations that are not condition failures" do
    reason = Aws::DynamoDB::Types::CancellationReason.new(code: "TransactionConflict")
    error  = Aws::DynamoDB::Errors::TransactionCanceledException.new(nil, "conflict", cancellation_reasons: [ reason ])
    allow(Dynamo.client).to receive(:transact_write_items).and_raise(error)

    expect { described_class.call(start_envelope(uuid: uuid, parts: [])) }
      .to raise_error(Aws::DynamoDB::Errors::TransactionCanceledException)
  end
end
