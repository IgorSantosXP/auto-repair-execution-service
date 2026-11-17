require "swagger_helper"

RSpec.describe "Stock movements", type: :request do
  let(:Authorization) { "Bearer #{admin_token}" }
  let(:part_id) { create_part(id: "p1", stock: 10)["id"] }

  path "/api/v1/parts/{part_id}/stock_movements" do
    parameter name: :part_id, in: :path, type: :string

    get "Lists the stock movements of a part (latest first)" do
      tags "Stock"
      security [ bearerAuth: [] ]
      produces "application/json"
      parameter name: :limit, in: :query, type: :integer, required: false

      response "200", "movements returned" do
        before do
          part_id
          Inventory::UseCases::RegisterMovement.call(part_id: "p1", movement_type: "outbound", quantity: 3)
        end

        run_test! do |response|
          json = JSON.parse(response.body)
          expect(json.map { |m| m["movement_type"] }).to eq(%w[outbound inbound])
          expect(json.first.keys).to include("id", "part_id", "quantity", "reason", "reference", "created_at")
        end
      end

      response "404", "part not found" do
        let(:part_id) { "nope" }
        run_test!
      end
    end

    post "Registers a stock movement" do
      tags "Stock"
      security [ bearerAuth: [] ]
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          movement_type: { type: :string, enum: %w[inbound outbound adjustment_in adjustment_out] },
          quantity: { type: :integer, example: 5 },
          reason: { type: :string }
        },
        required: %w[movement_type quantity]
      }

      response "201", "inbound registered" do
        let(:body) { { movement_type: "inbound", quantity: 5, reason: "purchase" } }
        run_test! { expect(stock_of("p1")).to eq(15) }
      end

      response "201", "outbound registered" do
        let(:body) { { movement_type: "outbound", quantity: 10 } }
        run_test! { expect(stock_of("p1")).to eq(0) }
      end

      response "422", "outbound below zero" do
        let(:body) { { movement_type: "outbound", quantity: 11 } }

        run_test! do |response|
          expect(JSON.parse(response.body)["error"]["details"].first).to include("Insufficient stock")
          expect(stock_of("p1")).to eq(10)
        end
      end

      response "422", "invalid type" do
        let(:body) { { movement_type: "reservation", quantity: 1 } }
        run_test!
      end

      response "422", "invalid quantity" do
        let(:body) { { movement_type: "inbound", quantity: 0 } }
        run_test!
      end

      response "404", "part not found" do
        let(:part_id) { "nope" }
        let(:body) { { movement_type: "inbound", quantity: 1 } }
        run_test!
      end
    end
  end
end
