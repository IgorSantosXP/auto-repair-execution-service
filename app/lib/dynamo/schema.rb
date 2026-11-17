module Dynamo
  # Single source of truth for the DynamoDB tables. The Terraform module that
  # provisions them on AWS mirrors this definition.
  module Schema
    PARTS              = "parts".freeze
    STOCK_MOVEMENTS    = "stock-movements".freeze
    EXECUTIONS         = "executions".freeze
    OUTBOX             = "outbox".freeze
    PROCESSED_MESSAGES = "processed-messages".freeze

    EXECUTIONS_STATUS_INDEX = "status-queued_at-index".freeze

    TABLES = {
      PARTS => {
        attributes: { "part_id" => "S" },
        key_schema: [ [ "part_id", "HASH" ] ]
      },
      STOCK_MOVEMENTS => {
        attributes: { "part_id" => "S", "movement_key" => "S" },
        key_schema: [ [ "part_id", "HASH" ], [ "movement_key", "RANGE" ] ]
      },
      EXECUTIONS => {
        attributes: { "service_order_uuid" => "S", "status" => "S", "queued_at" => "S" },
        key_schema: [ [ "service_order_uuid", "HASH" ] ],
        global_secondary_indexes: {
          EXECUTIONS_STATUS_INDEX => [ [ "status", "HASH" ], [ "queued_at", "RANGE" ] ]
        }
      },
      OUTBOX => {
        attributes: { "message_id" => "S" },
        key_schema: [ [ "message_id", "HASH" ] ]
      },
      PROCESSED_MESSAGES => {
        attributes: { "message_id" => "S" },
        key_schema: [ [ "message_id", "HASH" ] ],
        ttl_attribute: "expires_at"
      }
    }.freeze

    module_function

    def prefix
      ENV.fetch("DYNAMODB_TABLE_PREFIX", "auto-repair-local-execution")
    end

    def table_name(name)
      "#{prefix}-#{name}"
    end

    # Hash ready for Aws::DynamoDB::Client#create_table.
    def create_table_params(name)
      definition = TABLES.fetch(name)
      params = {
        table_name: table_name(name),
        billing_mode: "PAY_PER_REQUEST",
        attribute_definitions: definition[:attributes].map { |n, t| { attribute_name: n, attribute_type: t } },
        key_schema: key_schema(definition[:key_schema])
      }

      if definition[:global_secondary_indexes]
        params[:global_secondary_indexes] = definition[:global_secondary_indexes].map do |index_name, keys|
          { index_name: index_name, key_schema: key_schema(keys), projection: { projection_type: "ALL" } }
        end
      end

      params
    end

    def key_schema(keys)
      keys.map { |n, t| { attribute_name: n, key_type: t } }
    end
  end
end
