# Transactional outbox on DynamoDB. The outbox item is written inside the same
# TransactWriteItems as the state change; the relay (worker) publishes the
# pending items in created_at order and deletes each one after publishing.
module DynamoOutbox
  module_function

  def table
    Dynamo.table(Dynamo::Schema::OUTBOX)
  end

  def item_for(envelope)
    {
      "message_id" => envelope.message_id,
      "body"       => envelope.to_json,
      "created_at" => Dynamo.now_iso
    }
  end

  # Element for the `transact_items` list of TransactWriteItems.
  def transact_put(envelope)
    { put: { table_name: table, item: item_for(envelope) } }
  end

  def enqueue(envelope)
    Dynamo.client.put_item(table_name: table, item: item_for(envelope))
  end

  def pending
    Dynamo.paginate(:scan, table_name: table).sort_by { |item| item["created_at"] }
  end

  def relay
    published = 0
    pending.each do |item|
      Messaging.bus.publish(Messaging::Envelope.parse(item["body"]))
      Dynamo.client.delete_item(table_name: table, key: { "message_id" => item["message_id"] })
      published += 1
    end
    published
  end
end
