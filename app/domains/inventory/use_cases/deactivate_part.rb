module Inventory
  module UseCases
    # Soft delete: the part and its movement history stay, but it can no longer be reserved.
    class DeactivatePart
      def self.call(part_id:)
        UpdatePart.call(part_id: part_id, attributes: { "active" => false })
      end
    end
  end
end
