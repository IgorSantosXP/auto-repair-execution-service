require "rails_helper"

RSpec.describe Execution::UseCases::TransitionExecution do
  let(:uuid) { queue_execution }

  def transition(action, notes: nil, id: uuid)
    described_class.call(service_order_uuid: id, action: action, notes: notes)
  end

  def relayed_events
    DynamoOutbox.relay
    fake_bus.published
  end

  before do
    uuid
    DynamoOutbox.relay
    fake_bus.published.clear
  end

  it "walks queued -> in_diagnosis -> in_repair -> finished appending to the timeline" do
    expect(transition("start_diagnosis", notes: "diag")).to be_success
    expect(transition("start_repair", notes: "repair")).to be_success
    result = transition("finish", notes: "done")

    expect(result.payload).to include("status" => "finished")
    expect(result.payload["timeline"].map { |t| t["status"] }).to eq(%w[queued in_diagnosis in_repair finished])
    expect(result.payload["timeline"].last["notes"]).to eq("done")
    expect(result.payload).to include("diagnosis_notes" => "diag")
    expect(result.payload.values_at("started_at", "finished_at")).to all(be_present)
  end

  it "publishes the matching event for each transition" do
    transition("start_diagnosis", notes: "diag")
    transition("start_repair", notes: "repair")
    transition("finish", notes: "done")

    events = relayed_events
    expect(events.map(&:type)).to eq(%w[execution.diagnosis_started execution.repair_started execution.finished])
    expect(events.map { |e| e.payload["notes"] }).to eq(%w[diag repair done])
    expect(events.last.payload["finished_at"]).to be_present
    expect(events).to all(have_attributes(destination: "os", service_order_uuid: uuid))
  end

  it "emits status metrics" do
    expect(Telemetry).to receive(:status_transition).with(from: "queued", to: "in_diagnosis", duration_seconds: kind_of(Numeric))
    transition("start_diagnosis")
  end

  it "rejects invalid transitions pointing to the valid next action" do
    result = transition("finish")

    expect(result).to be_failure
    error = result.errors.first
    expect(error[:code]).to eq("invalid_transition")
    expect(error[:message]).to include("'queued'", "start_diagnosis")
    expect(relayed_events).to be_empty
  end

  it "says there is nothing left after finishing" do
    %w[start_diagnosis start_repair finish].each { |action| transition(action) }

    expect(transition("finish").errors.first[:message]).to include("no further transitions")
  end

  it "returns not_found for unknown executions" do
    expect(transition("start_diagnosis", id: SecureRandom.uuid).errors.first[:code]).to eq("not_found")
  end

  it "rejects the loser of a concurrent transition" do
    raced = false
    allow(Execution::Gateways::ExecutionRepository).to receive(:find).and_wrap_original do |original, id|
      item = original.call(id)
      unless raced
        raced = true
        transition("start_diagnosis") # another request wins the race after our read
      end
      item
    end

    result = transition("start_diagnosis")

    expect(result).to be_failure
    expect(result.errors.first[:code]).to eq("invalid_transition")
    expect(relayed_events.size).to eq(1)
  end

  it "re-raises cancellations that are not condition failures" do
    reason = Aws::DynamoDB::Types::CancellationReason.new(code: "TransactionConflict")
    error  = Aws::DynamoDB::Errors::TransactionCanceledException.new(nil, "conflict", cancellation_reasons: [ reason ])
    allow(Dynamo.client).to receive(:transact_write_items).and_raise(error)

    expect { transition("start_diagnosis") }.to raise_error(Aws::DynamoDB::Errors::TransactionCanceledException)
  end
end
