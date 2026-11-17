module Dynamo
  # Creates the tables (and the TTL on processed-messages) when they do not exist.
  # Idempotent and safe to run from several processes at once.
  class Provisioner
    def initialize(client: Dynamo.client, wait_for_endpoint: 60)
      @client            = client
      @wait_for_endpoint = wait_for_endpoint
    end

    def call
      wait_for_endpoint
      Schema::TABLES.each_key { |name| ensure_table(name) }
      Schema::TABLES.each_key { |name| ensure_ttl(name) }
    end

    private

    def ensure_table(name)
      @client.create_table(Schema.create_table_params(name))
    rescue Aws::DynamoDB::Errors::ResourceInUseException
      nil
    ensure
      @client.wait_until(:table_exists, table_name: Schema.table_name(name))
    end

    def ensure_ttl(name)
      attribute = Schema::TABLES.fetch(name)[:ttl_attribute]
      return unless attribute

      @client.update_time_to_live(
        table_name: Schema.table_name(name),
        time_to_live_specification: { enabled: true, attribute_name: attribute }
      )
    rescue Aws::DynamoDB::Errors::ValidationException
      nil # already enabled
    end

    def wait_for_endpoint
      deadline = Time.now + @wait_for_endpoint
      begin
        @client.list_tables(limit: 1)
      rescue Seahorse::Client::NetworkingError, Aws::Errors::ServiceError
        raise if Time.now > deadline

        sleep 2
        retry
      end
    end
  end
end
