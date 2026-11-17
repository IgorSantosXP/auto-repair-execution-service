module Execution
  module Serializer
    FIELDS = %w[service_order_uuid saga_id status vehicle services parts notes diagnosis_notes
                timeline queued_at started_at finished_at].freeze

    def self.call(item)
      FIELDS.index_with { |field| item[field] }
    end
  end
end
