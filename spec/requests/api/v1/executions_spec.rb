require "swagger_helper"

RSpec.describe "Executions", type: :request do
  let(:Authorization) { "Bearer #{admin_token}" }
  let(:service_order_uuid) { queue_execution(parts: []) }

  path "/api/v1/executions" do
    get "Lists the execution queue" do
      tags "Executions"
      security [ bearerAuth: [] ]
      produces "application/json"
      parameter name: :status, in: :query, type: :string, required: false,
                description: "queued, in_diagnosis, in_repair or finished"

      response "200", "queue ordered by priority" do
        before do
          queued_a = queue_execution
          sleep 0.01
          queued_b = queue_execution
          repair   = queue_execution
          %w[start_diagnosis start_repair].each do |action|
            Execution::UseCases::TransitionExecution.call(service_order_uuid: repair, action: action)
          end
          diagnosis = queue_execution
          Execution::UseCases::TransitionExecution.call(service_order_uuid: diagnosis, action: "start_diagnosis")
          @expected = [ repair, diagnosis, queued_a, queued_b ]
        end

        run_test! do |response|
          expect(JSON.parse(response.body).map { |e| e["service_order_uuid"] }).to eq(@expected)
        end
      end

      response "200", "filtered by status" do
        let(:status) { "finished" }
        before { queue_execution }

        run_test! { |response| expect(JSON.parse(response.body)).to eq([]) }
      end

      response "422", "unknown status" do
        let(:status) { "bogus" }
        run_test!
      end

      response "401", "unauthorized" do
        let(:Authorization) { nil }
        run_test!
      end
    end
  end

  path "/api/v1/executions/{service_order_uuid}" do
    parameter name: :service_order_uuid, in: :path, type: :string

    get "Shows an execution" do
      tags "Executions"
      security [ bearerAuth: [] ]
      produces "application/json"

      response "200", "execution returned" do
        run_test! do |response|
          json = JSON.parse(response.body)
          expect(json).to include("service_order_uuid" => service_order_uuid, "status" => "queued")
          expect(json["timeline"].first).to include("status" => "queued")
        end
      end

      response "404", "execution not found" do
        let(:service_order_uuid) { SecureRandom.uuid }
        run_test!
      end
    end
  end

  {
    "start_diagnosis" => [ "queued", "in_diagnosis", "execution.diagnosis_started", [] ],
    "start_repair"    => [ "in_diagnosis", "in_repair", "execution.repair_started", [ "start_diagnosis" ] ],
    "finish"          => [ "in_repair", "finished", "execution.finished", %w[start_diagnosis start_repair] ]
  }.each do |action, (from, to, event, previous)|
    path "/api/v1/executions/{service_order_uuid}/#{action}" do
      parameter name: :service_order_uuid, in: :path, type: :string
      parameter name: :body, in: :body, required: false, schema: { type: :object, properties: { notes: { type: :string } } }
      let(:body) { { notes: "observação" } }

      post "Moves the execution from #{from} to #{to}" do
        tags "Executions"
        security [ bearerAuth: [] ]
        consumes "application/json"
        produces "application/json"

        response "200", "transition applied" do
          before do
            service_order_uuid
            previous.each do |step|
              Execution::UseCases::TransitionExecution.call(service_order_uuid: service_order_uuid, action: step)
            end
            DynamoOutbox.relay
            fake_bus.published.clear
          end

          run_test! do |response|
            expect(JSON.parse(response.body)["status"]).to eq(to)
            DynamoOutbox.relay
            expect(fake_bus.types).to eq([ event ])
            expect(fake_bus.published.first.payload["notes"]).to eq("observação")
          end
        end

        response "422", "invalid transition" do
          before do
            (previous + [ action ]).each do |step|
              Execution::UseCases::TransitionExecution.call(service_order_uuid: service_order_uuid, action: step)
            end
          end

          run_test! do |response|
            expect(JSON.parse(response.body)["error"]).to include("code" => "invalid_transition")
          end
        end

        response "404", "execution not found" do
          let(:service_order_uuid) { SecureRandom.uuid }
          run_test!
        end
      end
    end
  end
end
