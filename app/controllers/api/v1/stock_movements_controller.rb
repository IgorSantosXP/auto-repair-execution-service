module Api
  module V1
    class StockMovementsController < BaseController
      before_action :load_part

      def index
        limit = params[:limit].to_i
        limit = 100 unless limit.between?(1, 500)
        movements = Inventory::Gateways::StockMovementRepository.for_part(@part["part_id"], limit: limit)

        render_success(movements.map { |movement| Inventory::Gateways::StockMovementRepository.serialize(movement) })
      end

      def create
        result = Inventory::UseCases::RegisterMovement.call(
          part_id: @part["part_id"],
          movement_type: params[:movement_type].to_s,
          quantity: params[:quantity],
          reason: params[:reason]
        )
        result.success? ? render_created(result.payload) : render_failure(result)
      end

      private

      def load_part
        @part = Inventory::Gateways::PartRepository.find(params[:part_id])
        render_not_found("Part not found") unless @part
      end
    end
  end
end
