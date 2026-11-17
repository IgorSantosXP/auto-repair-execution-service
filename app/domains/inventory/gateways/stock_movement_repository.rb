module Inventory
  module Gateways
    class StockMovementRepository
      def self.table
        Dynamo.table(Dynamo::Schema::STOCK_MOVEMENTS)
      end

      def self.build_item(part_id:, movement_type:, quantity:, reason: nil, reference: nil)
        now = Time.now.utc
        {
          "part_id"       => part_id,
          "movement_key"  => "#{now.iso8601(6)}##{SecureRandom.uuid}",
          "movement_type" => movement_type,
          "quantity"      => quantity,
          "reason"        => reason,
          "reference"     => reference,
          "created_at"    => now.iso8601(6)
        }.compact
      end

      # Element for TransactWriteItems.
      def self.transact_put(**attributes)
        { put: { table_name: table, item: build_item(**attributes) } }
      end

      def self.for_part(part_id, limit: 100)
        Dynamo.client.query(
          table_name: table,
          key_condition_expression: "part_id = :id",
          expression_attribute_values: { ":id" => part_id },
          scan_index_forward: false,
          limit: limit
        ).items.map { |item| Dynamo.plain(item) }
      end

      def self.serialize(item)
        {
          id:            item["movement_key"],
          part_id:       item["part_id"],
          movement_type: item["movement_type"],
          quantity:      item["quantity"],
          reason:        item["reason"],
          reference:     item["reference"],
          created_at:    item["created_at"]
        }
      end
    end
  end
end
