module Execution
  module Queries
    class FindExecution
      def self.call(service_order_uuid)
        item = Gateways::ExecutionRepository.find(service_order_uuid)
        return Result.failure(errors: [ { code: "not_found", message: "Execution not found" } ]) unless item

        Result.success(payload: Serializer.call(item))
      end
    end
  end
end
