module Inventory
  module UseCases
    class RegisterMovement
      def self.call(part_id:, movement_type:, quantity:, reason: nil, reference: nil)
        unless MovementTypes::MANUAL.include?(movement_type)
          return Result.failure(errors: [ "Invalid movement type '#{movement_type}'" ])
        end

        quantity = Integer(quantity.to_s, 10) rescue 0
        return Result.failure(errors: [ "Quantity must be greater than 0" ]) if quantity < 1

        debit = MovementTypes::DEBIT.include?(movement_type)
        movement = Gateways::StockMovementRepository.build_item(
          part_id: part_id, movement_type: movement_type, quantity: quantity, reason: reason, reference: reference
        )

        Dynamo.client.transact_write_items(transact_items: [
          stock_update(part_id, quantity, debit),
          { put: { table_name: Gateways::StockMovementRepository.table, item: movement } }
        ])
        Result.success(payload: Gateways::StockMovementRepository.serialize(Dynamo.plain(movement)))
      rescue Aws::DynamoDB::Errors::TransactionCanceledException
        failure_for(part_id, quantity)
      end

      # The condition makes the "never below zero" rule atomic with the update.
      def self.stock_update(part_id, quantity, debit)
        {
          update: {
            table_name: Gateways::PartRepository.table,
            key: { "part_id" => part_id },
            update_expression: "SET stock_quantity = stock_quantity #{debit ? '-' : '+'} :q, updated_at = :now",
            condition_expression: debit ? "attribute_exists(part_id) AND stock_quantity >= :q" : "attribute_exists(part_id)",
            expression_attribute_values: { ":q" => quantity, ":now" => Dynamo.now_iso }
          }
        }
      end

      def self.failure_for(part_id, quantity)
        part = Gateways::PartRepository.find(part_id)
        return Result.failure(errors: [ { code: "not_found", message: "Part not found" } ]) unless part

        Result.failure(errors: [
          "Insufficient stock for '#{part['name']}': available #{part['stock_quantity']}, requested #{quantity}"
        ])
      end

      private_class_method :stock_update, :failure_for
    end
  end
end
