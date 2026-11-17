require "rails_helper"

RSpec.describe "Messaging" do
  let(:envelope_json) do
    { message_id: "m1", type: "execution.start", kind: "command", source: "os-service", destination: "execution",
      saga_id: "s1", service_order_uuid: "u1", payload: { parts: [] } }.to_json
  end

  describe Messaging::Envelope do
    it "parses and serializes" do
      envelope = described_class.parse(envelope_json)

      expect(envelope).to have_attributes(type: "execution.start", correlation_id: "s1", trace: {})
      expect(envelope.to_h.keys).to include("message_id", "correlation_id", "payload")
      expect(envelope.log_context).to include(saga_id: "s1")
    end

    it "rejects unknown kinds" do
      expect { described_class.new(JSON.parse(envelope_json).merge("kind" => "x")) }.to raise_error(ArgumentError)
    end

    it "builds events addressed to the OS service" do
      event = described_class.event("execution.queued", payload: {}, saga_id: "s", service_order_uuid: "u")
      expect(event).to have_attributes(destination: "os", source: "execution-service", kind: "event")
    end
  end

  describe Messaging::Bus do
    it "publishes to SNS with the routing attributes" do
      client = instance_double(Aws::SNS::Client, publish: nil)
      envelope = Messaging::Envelope.parse(envelope_json)

      described_class.new(client: client, topic_arn: "arn:topic").publish(envelope)

      expect(client).to have_received(:publish).with(
        hash_including(topic_arn: "arn:topic",
                       message_attributes: hash_including("destination" => { data_type: "String", string_value: "execution" }))
      )
    end
  end

  describe Messaging::Consumer do
    let(:sqs)      { instance_double(Aws::SQS::Client, delete_message: nil) }
    let(:consumer) { described_class.new(handlers: Messaging::Handlers::REGISTRY, idempotency: Messaging::DynamoIdempotency.new, queue_url: "q", client: sqs) }

    def sqs_message(body)
      Struct.new(:body, :receipt_handle).new(body, "rh")
    end

    def start_body(uuid, parts)
      start_envelope(uuid: uuid, parts: parts).to_json
    end

    it "processes execution.start end to end and deletes the message" do
      create_part(id: "oleo", stock: 5)
      uuid = SecureRandom.uuid

      expect(consumer.process(sqs_message(start_body(uuid, [ { "part_id" => "oleo", "name" => "Oleo", "quantity" => 2 } ])))).to be(true)

      expect(stock_of("oleo")).to eq(3)
      expect(sqs).to have_received(:delete_message)
    end

    it "ignores duplicate deliveries of the same message_id" do
      create_part(id: "oleo", stock: 5)
      body = start_body(SecureRandom.uuid, [ { "part_id" => "oleo", "name" => "Oleo", "quantity" => 2 } ])

      2.times { consumer.process(sqs_message(body)) }

      expect(stock_of("oleo")).to eq(3)
      expect(sqs).to have_received(:delete_message).twice
    end

    it "discards messages without handler" do
      body = JSON.parse(envelope_json).merge("type" => "billing.unknown").to_json

      consumer.process(sqs_message(body))
      expect(sqs).to have_received(:delete_message)
    end

    it "leaves the message on the queue when the handler fails" do
      allow(Messaging::Handlers::StartExecution).to receive(:call).and_raise("boom")
      body = start_body(SecureRandom.uuid, [])

      expect(consumer.process(sqs_message(body))).to be(false)
      expect(sqs).not_to have_received(:delete_message)
      expect(consumer.process(sqs_message("not json"))).to be(false)
    end

    it "polls the queue" do
      response = Struct.new(:messages).new([ sqs_message(start_body(SecureRandom.uuid, [])) ])
      allow(sqs).to receive(:receive_message).and_return(response)

      expect(consumer.poll_once).to eq(1)
      iterations = 0
      consumer.run(stop: -> { (iterations += 1) > 1 })
      expect(sqs).to have_received(:receive_message).twice
    end
  end

  describe Messaging::Worker do
    it "relays the outbox until stopped" do
      relayed = 0
      consumer = instance_double(Messaging::Consumer)
      worker = described_class.new(consumer: consumer, relay: -> { relayed += 1 }, relay_interval: 0.01)
      allow(consumer).to receive(:run) do
        sleep 0.1
        worker.instance_variable_set(:@stopping, true)
      end
      allow(Signal).to receive(:trap)
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("QUEUE_URL").and_return("q")

      worker.start
      expect(relayed).to be >= 1
    end
  end

  describe Messaging::Provisioner do
    it "creates topic, queues and subscription" do
      sns = instance_double(Aws::SNS::Client)
      sqs = instance_double(Aws::SQS::Client)
      allow(Messaging).to receive_messages(sns: sns, sqs: sqs)
      allow(sns).to receive(:create_topic).and_return(double(topic_arn: "arn:topic"))
      allow(sqs).to receive(:create_queue).and_return(double(queue_url: "http://q"))
      allow(sqs).to receive(:get_queue_attributes).and_return(double(attributes: { "QueueArn" => "arn:q" }))
      allow(sns).to receive(:subscribe)

      result = described_class.new(destination: "execution", topic_name: "t", queue_name: "q").call

      expect(result).to eq(topic_arn: "arn:topic", queue_url: "http://q")
      expect(sns).to have_received(:subscribe).with(hash_including(attributes: hash_including("RawMessageDelivery" => "true")))
    ensure
      ENV.delete("EVENTS_TOPIC_ARN")
      ENV.delete("QUEUE_URL")
    end
  end

  describe Messaging::Tracing do
    it "is a no-op without datadog" do
      expect(described_class.inject).to eq({})
      expect(described_class.log_correlation).to eq({})
      expect(described_class.continue(Messaging::Envelope.parse(envelope_json)) { :ran }).to eq(:ran)
    end
  end

  describe Messaging::JsonLogger do
    it "writes JSON lines" do
      io = StringIO.new
      described_class.new(io).info("hello", saga_id: "s1")

      expect(JSON.parse(io.string)).to include("message" => "hello", "level" => "INFO", "saga_id" => "s1", "service" => "execution-service")
    end
  end

  describe Telemetry do
    it "is disabled without an agent host and never raises" do
      expect { described_class.stock_reservation(result: "reserved") }.not_to raise_error
      expect { described_class.status_transition(from: "queued", to: "in_diagnosis", duration_seconds: 1) }.not_to raise_error
    end

    it "emits namespaced metrics when enabled" do
      statsd = instance_double(Datadog::Statsd, increment: nil, distribution: nil) if defined?(Datadog::Statsd)
      skip "datadog not loaded" unless statsd
      allow(described_class).to receive(:client).and_return(statsd)

      described_class.status_transition(from: "queued", to: "in_diagnosis", duration_seconds: 3)

      expect(statsd).to have_received(:increment).with("execution.status_changed", tags: array_including("from:queued", "to:in_diagnosis"))
      expect(statsd).to have_received(:distribution).with("execution.duration", 3, tags: array_including("status:queued"))
    end
  end
end
