namespace :messaging do
  desc "Runs the worker: relays the outbox and consumes the execution queue"
  task work: :environment do
    Dynamo::Provisioner.new.call if ENV["DYNAMODB_AUTO_PROVISION"] == "true"

    if ENV["MESSAGING_AUTO_PROVISION"] == "true"
      Messaging::Provisioner.new(
        destination: "execution",
        topic_name:  ENV.fetch("EVENTS_TOPIC_NAME", "auto-repair-local-events"),
        queue_name:  ENV.fetch("QUEUE_NAME", "auto-repair-local-execution")
      ).call
    end

    consumer = Messaging::Consumer.new(handlers: Messaging::Handlers::REGISTRY, idempotency: Messaging::DynamoIdempotency.new)
    Messaging::Worker.new(consumer: consumer, relay: -> { DynamoOutbox.relay }).start
  end
end
