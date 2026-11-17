module Api
  module V1
    class ExecutionsController < BaseController
      def index
        result = Execution::Queries::ListQueue.call(status: params[:status])
        result.success? ? render_success(result.payload) : render_failure(result)
      end

      def show
        render_execution Execution::Queries::FindExecution.call(params[:service_order_uuid])
      end

      Execution::Statuses::TRANSITIONS.each_key do |action|
        define_method(action) do
          render_execution Execution::UseCases::TransitionExecution.call(
            service_order_uuid: params[:service_order_uuid], action: action, notes: params[:notes]
          )
        end
      end

      private

      def render_execution(result)
        result.success? ? render_success(result.payload) : render_failure(result)
      end
    end
  end
end
