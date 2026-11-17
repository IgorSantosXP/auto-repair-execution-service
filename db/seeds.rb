# Demo catalog with fixed ids so the other services can reference them.
# kit-embreagem has no stock on purpose: it triggers the saga compensation.
PARTS = [
  { id: "oleo-5w30",      sku: "OLEO-5W30",      name: "Óleo 5W30 1L",             unit_price_cents: 4_500,  stock_quantity: 50 },
  { id: "filtro-oleo",    sku: "FILTRO-OLEO",    name: "Filtro de óleo",           unit_price_cents: 3_500,  stock_quantity: 30 },
  { id: "pastilha-freio", sku: "PASTILHA-FREIO", name: "Jogo de pastilhas de freio", unit_price_cents: 18_000, stock_quantity: 10 },
  { id: "kit-embreagem",  sku: "KIT-EMBREAGEM",  name: "Kit de embreagem",         unit_price_cents: 89_000, stock_quantity: 0 }
].freeze

PARTS.each do |attributes|
  if Inventory::Gateways::PartRepository.find(attributes[:id])
    puts "Part #{attributes[:id]} already exists"
  else
    result = Inventory::UseCases::CreatePart.call(**attributes)
    puts result.success? ? "Part #{attributes[:id]} created" : "Part #{attributes[:id]}: #{result.errors.join(', ')}"
  end
end
