module Messaging
  # Consumer-side deduplication: the first delivery of a message_id claims it
  # with a conditional put; redeliveries are ignored. If the handler raises,
  # the claim is released so the retry can process the message again.
  class DynamoIdempotency
    TTL = 7.days

    def once(message_id)
      return false unless claim(message_id)

      begin
        yield
        true
      rescue StandardError
        release(message_id)
        raise
      end
    end

    private

    def table
      Dynamo.table(Dynamo::Schema::PROCESSED_MESSAGES)
    end

    def claim(message_id)
      Dynamo.client.put_item(
        table_name: table,
        item: {
          "message_id" => message_id,
          "created_at" => Dynamo.now_iso,
          "expires_at" => TTL.from_now.to_i
        },
        condition_expression: "attribute_not_exists(message_id)"
      )
      true
    rescue Aws::DynamoDB::Errors::ConditionalCheckFailedException
      false
    end

    def release(message_id)
      Dynamo.client.delete_item(table_name: table, key: { "message_id" => message_id })
    end
  end
end
