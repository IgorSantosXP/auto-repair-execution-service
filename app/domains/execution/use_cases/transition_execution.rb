module Execution
  module UseCases
    # start_diagnosis / start_repair / finish. The status check is repeated as a
    # condition of the write, so two concurrent requests cannot both succeed.
    class TransitionExecution
      TIMESTAMPS = { "start_diagnosis" => "started_at", "finish" => "finished_at" }.freeze

      def self.call(service_order_uuid:, action:, notes: nil)
        new(service_order_uuid, action, notes).call
      end

      def initialize(service_order_uuid, action, notes)
        @uuid   = service_order_uuid
        @action = action
        @notes  = notes
        @from, @to, @event_type = Statuses::TRANSITIONS.fetch(action)
      end

      def call
        item = Gateways::ExecutionRepository.find(@uuid)
        return failure("not_found", "Execution not found") unless item
        return invalid_transition(item["status"]) unless item["status"] == @from

        now = Time.now.utc
        Dynamo.client.transact_write_items(transact_items: [ update_item(item, now), outbox_item(item, now) ])
        Telemetry.status_transition(from: @from, to: @to, duration_seconds: duration(item, now))

        Queries::FindExecution.call(@uuid)
      rescue Aws::DynamoDB::Errors::TransactionCanceledException => e
        raise e unless Dynamo.cancellation_codes(e).first == "ConditionalCheckFailed"

        invalid_transition(Gateways::ExecutionRepository.find(@uuid)&.dig("status"))
      end

      private

      def update_item(item, now)
        iso    = now.iso8601(6)
        sets   = [ "#s = :to", "timeline = list_append(timeline, :entry)" ]
        names  = { "#s" => "status" }
        values = { ":to" => @to, ":from" => @from, ":entry" => [ { "status" => @to, "at" => iso, "notes" => @notes }.compact ] }

        if (attribute = TIMESTAMPS[@action])
          sets << "#{attribute} = :at"
          values[":at"] = iso
        end
        if @action == "start_diagnosis" && @notes.present?
          sets << "diagnosis_notes = :notes"
          values[":notes"] = @notes
        end

        {
          update: {
            table_name: Gateways::ExecutionRepository.table,
            key: { "service_order_uuid" => item["service_order_uuid"] },
            update_expression: "SET #{sets.join(', ')}",
            condition_expression: "#s = :from",
            expression_attribute_names: names,
            expression_attribute_values: values
          }
        }
      end

      def outbox_item(item, now)
        body = { notes: @notes }
        body[:finished_at] = now.iso8601(3) if @action == "finish"
        DynamoOutbox.transact_put(
          Messaging::Envelope.event(@event_type, payload: body, saga_id: item["saga_id"], service_order_uuid: @uuid)
        )
      end

      # Seconds spent in the status that is being left.
      def duration(item, now)
        entered = item["timeline"]&.last&.dig("at") || item["queued_at"]
        [ now - Time.iso8601(entered), 0 ].max
      end

      def invalid_transition(status)
        next_action = Statuses.next_action(status)
        hint = next_action ? "valid next action is '#{next_action}'" : "no further transitions are possible"
        failure("invalid_transition", "Cannot #{@action} an execution that is '#{status}'; #{hint}")
      end

      def failure(code, message)
        Result.failure(errors: [ { code: code, message: message } ])
      end
    end
  end
end
