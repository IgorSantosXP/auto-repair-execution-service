require "rails_helper"

RSpec.describe DynamoOutbox do
  def envelope(type = "execution.queued", uuid = SecureRandom.uuid)
    Messaging::Envelope.event(type, payload: { "position" => 1 }, saga_id: SecureRandom.uuid, service_order_uuid: uuid)
  end

  it "publishes pending items in created_at order and deletes them" do
    first  = envelope("execution.queued")
    second = envelope("execution.finished")
    described_class.enqueue(second) # written first on purpose... created_at decides, not the key
    sleep 0.01
    described_class.enqueue(first)

    expect(described_class.relay).to eq(2)
    expect(fake_bus.published.map(&:message_id)).to eq([ second.message_id, first.message_id ])
    expect(described_class.pending).to be_empty
  end

  it "keeps the item when publishing fails so it is retried" do
    described_class.enqueue(envelope)
    allow(fake_bus).to receive(:publish).and_raise("sns down")

    expect { described_class.relay }.to raise_error("sns down")
    expect(described_class.pending.size).to eq(1)
  end

  it "preserves the envelope through the outbox body" do
    original = envelope
    described_class.enqueue(original)

    described_class.relay
    expect(fake_bus.published.first.to_h).to eq(original.to_h)
  end

  it "does nothing when empty" do
    expect(described_class.relay).to eq(0)
  end
end
