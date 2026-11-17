ENV["RAILS_ENV"] = "test"
ENV["JWT_SECRET"] ||= "test_secret"
ENV["DYNAMODB_TABLE_PREFIX"] ||= "auto-repair-test-execution"

require_relative "../../config/environment"
require "rack/test"
require "webmock/cucumber"

WebMock.disable_net_connect!(allow: [ "localstack", "localhost", "127.0.0.1" ])

Dynamo::Provisioner.new.call

module ExecutionWorld
  include Rack::Test::Methods

  def app
    Rails.application
  end

  def json
    JSON.parse(last_response.body)
  end

  def admin_token
    Identity::Services::JwtEncoder.encode({ "sub" => "1" })
  end

  def outbox_events
    DynamoOutbox.pending.map { |item| JSON.parse(item["body"]) }
  end

  def clean_tables!
    Dynamo::Schema::TABLES.each do |name, definition|
      table = Dynamo::Schema.table_name(name)
      keys  = definition[:key_schema].map(&:first)
      Dynamo.paginate(:scan, table_name: table).each do |item|
        Dynamo.client.delete_item(table_name: table, key: item.slice(*keys))
      end
    end
  end
end
World(ExecutionWorld)

Before do
  clean_tables!
  Messaging.logger = Messaging::JsonLogger.new(StringIO.new)
end
