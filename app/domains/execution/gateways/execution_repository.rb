module Execution
  module Gateways
    class ExecutionRepository
      TABLE = Dynamo::Schema::EXECUTIONS
      INDEX = Dynamo::Schema::EXECUTIONS_STATUS_INDEX

      def self.table
        Dynamo.table(TABLE)
      end

      def self.find(service_order_uuid)
        item = Dynamo.client.get_item(
          table_name: table, key: { "service_order_uuid" => service_order_uuid }, consistent_read: true
        ).item
        item && Dynamo.plain(item)
      end

      # Items of one status, oldest queued_at first (GSI query, never a scan).
      def self.by_status(status)
        Dynamo.paginate(
          :query,
          table_name: table,
          index_name: INDEX,
          key_condition_expression: "#s = :status",
          expression_attribute_names: { "#s" => "status" },
          expression_attribute_values: { ":status" => status },
          scan_index_forward: true
        )
      end

      def self.count_by_status(status)
        total = 0
        params = {
          table_name: table,
          index_name: INDEX,
          select: "COUNT",
          key_condition_expression: "#s = :status",
          expression_attribute_names: { "#s" => "status" },
          expression_attribute_values: { ":status" => status }
        }
        loop do
          response = Dynamo.client.query(**params)
          total += response.count
          break if response.last_evaluated_key.blank?

          params = params.merge(exclusive_start_key: response.last_evaluated_key)
        end
        total
      end
    end
  end
end
