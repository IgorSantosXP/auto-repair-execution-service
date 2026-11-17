require "rails_helper"

RSpec.describe Inventory::UseCases::RegisterMovement do
  before { create_part(id: "p1", stock: 5) }

  def register(**args)
    described_class.call(part_id: "p1", **args)
  end

  it "applies credits and debits to the stock" do
    register(movement_type: "adjustment_in", quantity: 4)
    register(movement_type: "adjustment_out", quantity: 2)

    expect(stock_of("p1")).to eq(7)
  end

  it "refuses to go below zero" do
    result = register(movement_type: "outbound", quantity: 6)

    expect(result).to be_failure
    expect(result.errors.first).to include("available 5", "requested 6")
    expect(stock_of("p1")).to eq(5)
  end

  it "returns not_found for unknown parts" do
    result = described_class.call(part_id: "ghost", movement_type: "outbound", quantity: 1)
    expect(result.errors.first[:code]).to eq("not_found")
  end

  it "validates type and quantity" do
    expect(register(movement_type: "release", quantity: 1)).to be_failure
    expect(register(movement_type: "inbound", quantity: "x")).to be_failure
  end
end
