require "rails_helper"

RSpec.describe Dynamo::Provisioner do
  it "is idempotent and creates the schema" do
    2.times { described_class.new.call }

    tables = Dynamo.client.list_tables.table_names
    Dynamo::Schema::TABLES.each_key { |name| expect(tables).to include(Dynamo::Schema.table_name(name)) }

    executions = Dynamo.client.describe_table(table_name: Dynamo.table("executions")).table
    expect(executions.global_secondary_indexes.map(&:index_name)).to eq([ "status-queued_at-index" ])
    expect(Dynamo.client.describe_time_to_live(table_name: Dynamo.table("processed-messages")).time_to_live_description.attribute_name).to eq("expires_at")
  end

  it "retries until the endpoint answers" do
    client = instance_double(Aws::DynamoDB::Client)
    calls = 0
    allow(client).to receive(:list_tables) { (calls += 1) < 2 ? raise(Seahorse::Client::NetworkingError.new(StandardError.new("down"))) : nil }
    allow(client).to receive(:create_table)
    allow(client).to receive(:wait_until)
    allow(client).to receive(:update_time_to_live)
    provisioner = described_class.new(client: client)
    allow(provisioner).to receive(:sleep)

    provisioner.call
    expect(calls).to eq(2)
  end
end
