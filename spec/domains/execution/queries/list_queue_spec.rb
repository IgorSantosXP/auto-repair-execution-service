require "rails_helper"

RSpec.describe Execution::Queries::ListQueue do
  it "orders by status priority and then by oldest queued_at" do
    first  = queue_execution
    second = queue_execution
    repair = queue_execution
    %w[start_diagnosis start_repair].each { |a| Execution::UseCases::TransitionExecution.call(service_order_uuid: repair, action: a) }

    uuids = described_class.call.payload.map { |e| e["service_order_uuid"] }
    expect(uuids).to eq([ repair, first, second ])
  end

  it "excludes finished executions unless filtered" do
    done = queue_execution
    %w[start_diagnosis start_repair finish].each { |a| Execution::UseCases::TransitionExecution.call(service_order_uuid: done, action: a) }

    expect(described_class.call.payload).to be_empty
    expect(described_class.call(status: "finished").payload.map { |e| e["service_order_uuid"] }).to eq([ done ])
  end

  it "rejects unknown statuses" do
    expect(described_class.call(status: "bogus")).to be_failure
  end
end
