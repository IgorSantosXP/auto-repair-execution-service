module Messaging
  module Handlers
    module StartExecution
      module_function

      def call(envelope)
        Execution::UseCases::StartExecution.call(envelope)
      end
    end
  end
end
