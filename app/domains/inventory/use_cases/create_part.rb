module Inventory
  module UseCases
    class CreatePart
      def self.call(sku: nil, name: nil, unit_price_cents: nil, description: nil, stock_quantity: nil, id: nil)
        errors = validate(sku, name, unit_price_cents, stock_quantity)
        return Result.failure(errors: errors) if errors.any?

        stock = stock_quantity.to_i
        part_id = id.presence || SecureRandom.uuid
        return Result.failure(errors: [ "Part with SKU '#{sku}' already exists" ]) if sku_taken?(sku)

        now  = Dynamo.now_iso
        item = {
          "part_id" => part_id, "sku" => sku, "name" => name, "description" => description,
          "unit_price_cents" => unit_price_cents.to_i, "stock_quantity" => stock, "active" => true,
          "created_at" => now, "updated_at" => now
        }.compact

        items = [ { put: { table_name: Gateways::PartRepository.table, item: item,
                          condition_expression: "attribute_not_exists(part_id)" } } ]
        if stock.positive?
          items << Gateways::StockMovementRepository.transact_put(
            part_id: part_id, movement_type: "inbound", quantity: stock, reason: "initial_stock"
          )
        end

        Dynamo.client.transact_write_items(transact_items: items)
        Result.success(payload: Gateways::PartRepository.serialize(Dynamo.plain(item)))
      rescue Aws::DynamoDB::Errors::TransactionCanceledException
        Result.failure(errors: [ "Part '#{part_id}' already exists" ])
      end

      def self.validate(sku, name, price, stock)
        errors = []
        errors << "SKU can't be blank" if sku.blank?
        errors << "Name can't be blank" if name.blank?
        errors << "Unit price cents must be an integer greater than or equal to 0" unless non_negative_integer?(price)
        errors << "Stock quantity must be an integer greater than or equal to 0" unless stock.nil? || non_negative_integer?(stock)
        errors
      end

      def self.non_negative_integer?(value)
        Integer(value.to_s, 10) >= 0
      rescue ArgumentError, TypeError
        false
      end

      def self.sku_taken?(sku)
        Gateways::PartRepository.all.any? { |part| part["sku"] == sku }
      end

      private_class_method :validate, :non_negative_integer?, :sku_taken?
    end
  end
end
