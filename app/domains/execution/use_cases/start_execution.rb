module Execution
  module UseCases
    # Handles the `execution.start` command: reserves the stock for every part and
    # queues the execution in one TransactWriteItems (all or nothing), together with
    # the `execution.queued` outbox item. If any part is unavailable nothing is
    # written except the `execution.failed` outbox item.
    class StartExecution
      def self.call(envelope)
        new(envelope).call
      end

      def initialize(envelope)
        @envelope = envelope
        @payload  = envelope.payload
        @uuid     = envelope.service_order_uuid
        @parts    = aggregate_parts(@payload["parts"])
      end

      def call
        position = Gateways::ExecutionRepository.count_by_status(Statuses::QUEUED) + 1
        Dynamo.client.transact_write_items(transact_items: transaction(position))
        Telemetry.stock_reservation(result: "reserved")
        Result.success(payload: { position: position })
      rescue Aws::DynamoDB::Errors::TransactionCanceledException => e
        handle_cancellation(e)
      end

      private

      attr_reader :envelope, :payload, :uuid, :parts

      def aggregate_parts(list)
        Array(list).each_with_object({}) do |part, acc|
          quantity = part["quantity"].to_i
          next if part["part_id"].blank? || quantity < 1

          entry = (acc[part["part_id"]] ||= { "part_id" => part["part_id"], "name" => part["name"], "quantity" => 0 })
          entry["quantity"] += quantity
        end.values
      end

      # Order matters: cancellation_reasons come back in the same order as these items.
      def transaction(position)
        stock_updates + reservations + [ execution_put, DynamoOutbox.transact_put(queued_event(position)) ]
      end

      def stock_updates
        parts.map do |part|
          {
            update: {
              table_name: Inventory::Gateways::PartRepository.table,
              key: { "part_id" => part["part_id"] },
              update_expression: "SET stock_quantity = stock_quantity - :q, updated_at = :now",
              condition_expression: "attribute_exists(part_id) AND active = :true AND stock_quantity >= :q",
              expression_attribute_values: { ":q" => part["quantity"], ":true" => true, ":now" => Dynamo.now_iso }
            }
          }
        end
      end

      def reservations
        parts.map do |part|
          Inventory::Gateways::StockMovementRepository.transact_put(
            part_id: part["part_id"], movement_type: "reservation", quantity: part["quantity"],
            reason: "service_order", reference: uuid
          )
        end
      end

      def execution_put
        now = Dynamo.now_iso
        item = {
          "service_order_uuid" => uuid,
          "saga_id"            => envelope.saga_id,
          "status"             => Statuses::QUEUED,
          "vehicle"            => payload["vehicle"] || {},
          "services"           => Array(payload["services"]),
          "parts"              => parts,
          "notes"              => payload["notes"],
          "timeline"           => [ { "status" => Statuses::QUEUED, "at" => now, "notes" => payload["notes"] }.compact ],
          "queued_at"          => now
        }.compact

        { put: { table_name: Gateways::ExecutionRepository.table, item: item,
                 condition_expression: "attribute_not_exists(service_order_uuid)" } }
      end

      def queued_event(position)
        event("execution.queued", position: position)
      end

      def event(type, body)
        Messaging::Envelope.event(type, payload: body, saga_id: envelope.saga_id, service_order_uuid: uuid)
      end

      def handle_cancellation(error)
        codes = Dynamo.cancellation_codes(error)
        execution_index = parts.size * 2

        # The execution is already there: this command was processed before.
        return Result.success(payload: { duplicate: true }) if codes[execution_index] == "ConditionalCheckFailed"
        raise error unless codes.first(parts.size).include?("ConditionalCheckFailed")

        report_failure
      end

      def report_failure
        details = failure_details
        reason  = details.any? { |d| d[:unknown] } ? "unknown_part" : "insufficient_stock"
        details = details.map { |d| d.except(:unknown) }

        DynamoOutbox.enqueue(event("execution.failed", reason: reason, details: details))
        Telemetry.stock_reservation(result: "insufficient_stock", reason: reason)
        Result.failure(errors: [ { code: reason, message: "Could not reserve stock", details: details } ])
      end

      # Reads the current stock to tell the OS service exactly what is missing.
      def failure_details
        parts.filter_map do |part|
          current   = Inventory::Gateways::PartRepository.find(part["part_id"])
          available = current && current["active"] ? current["stock_quantity"].to_i : 0
          next if current && current["active"] && available >= part["quantity"]

          { part_id: part["part_id"], name: part["name"] || current&.dig("name"),
            requested: part["quantity"], available: available, unknown: current.nil? || !current["active"] }
        end
      end
    end
  end
end
