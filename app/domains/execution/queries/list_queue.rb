module Execution
  module Queries
    # The work queue: in_repair first, then in_diagnosis, then queued; oldest first within a status.
    class ListQueue
      def self.call(status: nil)
        statuses = status.present? ? [ status ] : Statuses::QUEUE
        invalid  = statuses - Statuses::ALL
        return Result.failure(errors: [ { code: "invalid_status", message: "Unknown status '#{invalid.first}'" } ]) if invalid.any?

        items = statuses.flat_map { |s| Gateways::ExecutionRepository.by_status(s) }
        Result.success(payload: items.map { |item| Serializer.call(item) })
      end
    end
  end
end
