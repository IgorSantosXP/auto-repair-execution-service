def start_command(uuid, quantity, part_id)
  @commands ||= {}
  @commands[uuid] ||= Messaging::Envelope.command(
    "execution.start", destination: "execution", saga_id: "saga-#{uuid}", service_order_uuid: uuid,
    payload: { "vehicle" => { "license_plate" => "ABC1D23" }, "services" => [ { "name" => "Revisão", "quantity" => 1 } ],
               "parts" => [ { "part_id" => part_id, "name" => part_id, "quantity" => quantity } ], "notes" => "" }
  )
end

def deliver(envelope)
  Messaging::DynamoIdempotency.new.once(envelope.message_id) do
    Messaging::Handlers::REGISTRY.fetch(envelope.type).call(envelope)
  end
end

Dado("que o catálogo tem a peça {string} com {int} unidades em estoque") do |part_id, stock|
  result = Inventory::UseCases::CreatePart.call(id: part_id, sku: part_id.upcase, name: "Óleo 5W30",
                                                unit_price_cents: 4500, stock_quantity: stock)
  expect(result).to be_success
end

Quando("o comando {string} chega para a OS {string} com {int} unidades de {string}") do |_type, uuid, quantity, part_id|
  deliver(start_command(uuid, quantity, part_id))
end

Quando("o comando {string} para a OS {string} com {int} unidade de {string} é entregue {int} vezes") do |_type, uuid, quantity, part_id, times|
  envelope = start_command(uuid, quantity, part_id)
  times.times { deliver(Messaging::Envelope.parse(envelope.to_json)) }
end

Quando("o mecânico avança a execução da OS {string} por diagnóstico, reparo e finalização") do |uuid|
  header "Authorization", "Bearer #{admin_token}"
  %w[start_diagnosis start_repair finish].each do |action|
    post "/api/v1/executions/#{uuid}/#{action}"
    expect(last_response.status).to eq(200), last_response.body
  end
end

Então("o estoque de {string} passa a ser {int}") do |part_id, stock|
  expect(Inventory::Gateways::PartRepository.find(part_id)["stock_quantity"]).to eq(stock)
end

Então("o estoque de {string} continua {int}") do |part_id, stock|
  expect(Inventory::Gateways::PartRepository.find(part_id)["stock_quantity"]).to eq(stock)
end

Então("o evento {string} é publicado para o OS Service") do |type|
  event = outbox_events.find { |e| e["type"] == type }
  expect(event).to include("destination" => "os")
end

Então("o evento {string} é publicado com o motivo {string}") do |type, reason|
  event = outbox_events.find { |e| e["type"] == type }
  expect(event.dig("payload", "reason")).to eq(reason)
end

Então("a OS {string} não entra na fila de execução") do |uuid|
  expect(Execution::Gateways::ExecutionRepository.find(uuid)).to be_nil
end

Então("a execução da OS {string} fica com status {string}") do |uuid, status|
  header "Authorization", "Bearer #{admin_token}"
  get "/api/v1/executions/#{uuid}"
  expect(json["status"]).to eq(status)
end

Então("os eventos {string} são publicados em ordem") do |list|
  expected  = list.split(",").map(&:strip)
  published = outbox_events.map { |e| e["type"] } & expected
  expect(published).to eq(expected)
end

Então("apenas {int} evento {string} é publicado") do |count, type|
  expect(outbox_events.count { |e| e["type"] == type }).to eq(count)
end
