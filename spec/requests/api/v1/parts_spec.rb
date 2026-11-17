require "swagger_helper"

RSpec.describe "Parts", type: :request do
  let(:Authorization) { "Bearer #{admin_token}" }

  path "/api/v1/parts" do
    get "Lists parts" do
      tags "Parts"
      security [ bearerAuth: [] ]
      produces "application/json"
      parameter name: :active, in: :query, type: :boolean, required: false
      parameter name: :name, in: :query, type: :string, required: false

      response "200", "parts returned" do
        before do
          create_part(id: "b-part", name: "Bravo")
          create_part(id: "a-part", name: "Alpha")
        end

        run_test! do |response|
          expect(JSON.parse(response.body).map { |p| p["id"] }).to eq(%w[a-part b-part])
        end
      end

      response "200", "filtered by active and name" do
        let(:active) { true }
        let(:name) { "alp" }
        before do
          create_part(id: "a-part", name: "Alpha")
          create_part(id: "b-part", name: "Bravo")
          Inventory::UseCases::DeactivatePart.call(part_id: "b-part")
        end

        run_test! do |response|
          expect(JSON.parse(response.body).map { |p| p["id"] }).to eq(%w[a-part])
        end
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { "Bearer invalid" }
        run_test!
      end
    end

    post "Creates a part" do
      tags "Parts"
      security [ bearerAuth: [] ]
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          id: { type: :string, example: "oleo-5w30", description: "Opcional; gerado (uuid) quando omitido" },
          sku: { type: :string, example: "OLEO-5W30" },
          name: { type: :string, example: "Óleo 5W30 1L" },
          description: { type: :string },
          unit_price_cents: { type: :integer, example: 4500 },
          stock_quantity: { type: :integer, example: 50, description: "Gera uma movimentação inbound inicial" }
        },
        required: %w[sku name unit_price_cents]
      }

      response "201", "part created" do
        let(:body) { { sku: "OLEO", name: "Óleo", unit_price_cents: 4500, stock_quantity: 5 } }

        run_test! do |response|
          json = JSON.parse(response.body)
          expect(json).to include("sku" => "OLEO", "stock_quantity" => 5, "active" => true)
          expect(json.keys).to match_array(%w[id sku name description unit_price_cents stock_quantity active created_at updated_at])
          expect(Inventory::Gateways::StockMovementRepository.for_part(json["id"]).first["movement_type"]).to eq("inbound")
        end
      end

      response "422", "validation error" do
        let(:body) { { sku: "", name: "", unit_price_cents: -1 } }
        run_test!
      end

      response "422", "duplicate id" do
        before { create_part(id: "dup") }
        let(:body) { { id: "dup", sku: "OTHER", name: "Outra", unit_price_cents: 100 } }
        run_test!
      end

      response "422", "duplicate sku" do
        before { create_part(id: "x", sku: "SAME") }
        let(:body) { { sku: "SAME", name: "Outra", unit_price_cents: 100 } }
        run_test!
      end
    end
  end

  path "/api/v1/parts/{id}" do
    parameter name: :id, in: :path, type: :string

    get "Shows a part" do
      tags "Parts"
      security [ bearerAuth: [] ]
      produces "application/json"

      response "200", "part returned" do
        let(:id) { create_part(id: "oleo-5w30")["id"] }
        run_test! { |response| expect(JSON.parse(response.body)["id"]).to eq("oleo-5w30") }
      end

      response "404", "part not found" do
        let(:id) { "nope" }
        run_test!
      end
    end

    patch "Updates a part" do
      tags "Parts"
      security [ bearerAuth: [] ]
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, schema: {
        type: :object,
        properties: {
          sku: { type: :string }, name: { type: :string }, description: { type: :string },
          unit_price_cents: { type: :integer }, active: { type: :boolean }
        }
      }

      response "200", "part updated" do
        let(:id) { create_part(id: "p1", stock: 7)["id"] }
        let(:body) { { name: "Novo nome", unit_price_cents: 9900, stock_quantity: 999 } }

        run_test! do |response|
          expect(JSON.parse(response.body)).to include("name" => "Novo nome", "unit_price_cents" => 9900, "stock_quantity" => 7)
        end
      end

      response "422", "invalid attributes" do
        let(:id) { create_part(id: "p1")["id"] }
        let(:body) { { name: "", unit_price_cents: "abc" } }
        run_test!
      end

      response "404", "part not found" do
        let(:id) { "nope" }
        let(:body) { { name: "x" } }
        run_test!
      end
    end

    delete "Deactivates a part (soft delete)" do
      tags "Parts"
      security [ bearerAuth: [] ]

      response "204", "part deactivated" do
        let(:id) { create_part(id: "p1")["id"] }

        run_test! do
          expect(Inventory::Gateways::PartRepository.find("p1")["active"]).to be(false)
        end
      end

      response "404", "part not found" do
        let(:id) { "nope" }
        run_test!
      end
    end
  end
end
