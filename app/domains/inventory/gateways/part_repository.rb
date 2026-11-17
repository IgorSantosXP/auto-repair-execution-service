module Inventory
  module Gateways
    class PartRepository
      def self.table
        Dynamo.table(Dynamo::Schema::PARTS)
      end

      def self.find(part_id)
        item = Dynamo.client.get_item(table_name: table, key: { "part_id" => part_id }, consistent_read: true).item
        item && Dynamo.plain(item)
      end

      # The catalog is small, so a scan is acceptable here (see README, access patterns).
      def self.all
        Dynamo.paginate(:scan, table_name: table, consistent_read: true).sort_by { |part| part["name"].to_s.downcase }
      end

      def self.serialize(item)
        {
          id:               item["part_id"],
          sku:              item["sku"],
          name:             item["name"],
          description:      item["description"],
          unit_price_cents: item["unit_price_cents"],
          stock_quantity:   item["stock_quantity"],
          active:           item["active"],
          created_at:       item["created_at"],
          updated_at:       item["updated_at"]
        }
      end
    end
  end
end
