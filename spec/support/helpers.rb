module ExecutionHelpers
  def fake_bus
    @fake_bus
  end

  def admin_token
    Identity::Services::JwtEncoder.encode({ "sub" => "1" })
  end

  def create_part(id: "oleo-5w30", stock: 10, **attrs)
    result = Inventory::UseCases::CreatePart.call(
      id: id, sku: attrs.fetch(:sku, id.upcase), name: attrs.fetch(:name, "Part #{id}"),
      unit_price_cents: attrs.fetch(:unit_price_cents, 1000), stock_quantity: stock
    )
    raise result.errors.inspect unless result.success?

    result.payload.stringify_keys
  end

  def stock_of(part_id)
    Inventory::Gateways::PartRepository.find(part_id)["stock_quantity"]
  end

  def start_envelope(uuid: SecureRandom.uuid, parts: [], saga_id: SecureRandom.uuid, notes: "Troca de óleo")
    Messaging::Envelope.command(
      "execution.start", destination: "execution", saga_id: saga_id, service_order_uuid: uuid,
      payload: { "vehicle" => { "license_plate" => "ABC1D23" }, "services" => [ { "name" => "Revisão", "quantity" => 1 } ],
                 "parts" => parts, "notes" => notes }
    )
  end

  def queue_execution(uuid: SecureRandom.uuid, parts: [])
    Execution::UseCases::StartExecution.call(start_envelope(uuid: uuid, parts: parts))
    uuid
  end

  def outbox_types
    DynamoOutbox.pending.map { |item| JSON.parse(item["body"])["type"] }
  end
end

RSpec.configure { |config| config.include ExecutionHelpers }
