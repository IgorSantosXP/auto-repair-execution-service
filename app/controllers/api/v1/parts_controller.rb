module Api
  module V1
    class PartsController < BaseController
      def index
        parts = Inventory::Gateways::PartRepository.all
        parts = parts.select { |part| part["active"] == ActiveModel::Type::Boolean.new.cast(params[:active]) } if params.key?(:active)
        parts = parts.select { |part| part["name"].to_s.downcase.include?(params[:name].downcase) } if params[:name].present?

        render_success(parts.map { |part| Inventory::Gateways::PartRepository.serialize(part) })
      end

      def show
        part = Inventory::Gateways::PartRepository.find(params[:id])
        return render_not_found("Part not found") unless part

        render_success(Inventory::Gateways::PartRepository.serialize(part))
      end

      def create
        result = Inventory::UseCases::CreatePart.call(
          **create_params.to_h.symbolize_keys
        )
        result.success? ? render_created(result.payload) : render_failure(result)
      end

      def update
        result = Inventory::UseCases::UpdatePart.call(part_id: params[:id], attributes: update_params)
        result.success? ? render_success(result.payload) : render_failure(result)
      end

      def destroy
        result = Inventory::UseCases::DeactivatePart.call(part_id: params[:id])
        result.success? ? render_no_content : render_failure(result)
      end

      private

      def create_params
        params.permit(:id, :sku, :name, :description, :unit_price_cents, :stock_quantity)
      end

      def update_params
        params.permit(:sku, :name, :description, :unit_price_cents, :active)
      end
    end
  end
end
