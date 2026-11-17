require "rails_helper"

RSpec.describe Messaging::DynamoIdempotency do
  subject(:idempotency) { described_class.new }

  it "runs the block once per message id" do
    calls = 0

    expect(idempotency.once("m1") { calls += 1 }).to be(true)
    expect(idempotency.once("m1") { calls += 1 }).to be(false)
    expect(idempotency.once("m2") { calls += 1 }).to be(true)
    expect(calls).to eq(2)
  end

  it "stores an expiry for the TTL" do
    idempotency.once("m1") { }
    item = Dynamo.client.get_item(table_name: Dynamo.table("processed-messages"), key: { "message_id" => "m1" }).item

    expect(item["expires_at"].to_i).to be_within(60).of(7.days.from_now.to_i)
  end

  it "releases the marker and re-raises when the block fails" do
    expect { idempotency.once("m1") { raise "boom" } }.to raise_error("boom")
    expect(idempotency.once("m1") { }).to be(true)
  end
end
