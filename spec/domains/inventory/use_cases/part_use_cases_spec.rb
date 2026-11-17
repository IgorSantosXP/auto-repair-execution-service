require "rails_helper"

RSpec.describe "Part use cases" do
  it "creates a part without initial stock and no movement" do
    result = Inventory::UseCases::CreatePart.call(sku: "S", name: "N", unit_price_cents: "100")

    expect(result.payload).to include(stock_quantity: 0, unit_price_cents: 100, active: true)
    expect(Inventory::Gateways::StockMovementRepository.for_part(result.payload[:id])).to be_empty
  end

  it "rejects a negative initial stock" do
    expect(Inventory::UseCases::CreatePart.call(sku: "S", name: "N", unit_price_cents: 1, stock_quantity: -1)).to be_failure
  end

  it "updates only the allowed attributes" do
    create_part(id: "p1", stock: 3)
    result = Inventory::UseCases::UpdatePart.call(part_id: "p1", attributes: { name: "Novo", stock_quantity: 99, active: "false" })

    expect(result.payload).to include(name: "Novo", stock_quantity: 3, active: false)
  end

  it "does not create a part when updating an unknown id" do
    result = Inventory::UseCases::UpdatePart.call(part_id: "ghost", attributes: { name: "x" })

    expect(result.errors.first[:code]).to eq("not_found")
    expect(Inventory::Gateways::PartRepository.find("ghost")).to be_nil
  end

  it "keeps the movement history when deactivating" do
    create_part(id: "p1", stock: 3)
    Inventory::UseCases::DeactivatePart.call(part_id: "p1")

    expect(Inventory::Gateways::PartRepository.find("p1")["active"]).to be(false)
    expect(Inventory::Gateways::StockMovementRepository.for_part("p1").size).to eq(1)
  end
end
