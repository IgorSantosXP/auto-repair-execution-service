module Inventory
  module UseCases
    class UpdatePart
      ATTRIBUTES = %w[sku name description unit_price_cents active].freeze

      # Stock is never edited directly: it only changes through stock movements.
      def self.call(part_id:, attributes:)
        attributes = attributes.to_h.stringify_keys.slice(*ATTRIBUTES)
        errors = validate(attributes)
        return Result.failure(errors: errors) if errors.any?

        names  = { "#updated_at" => "updated_at" }
        values = { ":updated_at" => Dynamo.now_iso }
        sets   = [ "#updated_at = :updated_at" ]

        attributes.each_with_index do |(key, value), i|
          names["#a#{i}"]  = key
          values[":v#{i}"] = key == "unit_price_cents" ? value.to_i : value
          sets << "#a#{i} = :v#{i}"
        end

        response = Dynamo.client.update_item(
          table_name: Gateways::PartRepository.table,
          key: { "part_id" => part_id },
          update_expression: "SET #{sets.join(', ')}",
          condition_expression: "attribute_exists(part_id)",
          expression_attribute_names: names,
          expression_attribute_values: values,
          return_values: "ALL_NEW"
        )
        Result.success(payload: Gateways::PartRepository.serialize(Dynamo.plain(response.attributes)))
      rescue Aws::DynamoDB::Errors::ConditionalCheckFailedException
        Result.failure(errors: [ { code: "not_found", message: "Part not found" } ])
      end

      def self.validate(attributes)
        errors = []
        errors << "SKU can't be blank" if attributes.key?("sku") && attributes["sku"].blank?
        errors << "Name can't be blank" if attributes.key?("name") && attributes["name"].blank?
        if attributes.key?("unit_price_cents") && !(Integer(attributes["unit_price_cents"].to_s, 10) >= 0 rescue false)
          errors << "Unit price cents must be an integer greater than or equal to 0"
        end
        if attributes.key?("active")
          attributes["active"] = ActiveModel::Type::Boolean.new.cast(attributes["active"])
        end
        errors
      end

      private_class_method :validate
    end
  end
end
