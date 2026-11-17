require "aws-sdk-dynamodb"

# DynamoDB access. Locally it talks to LocalStack through AWS_ENDPOINT_URL.
# The SDK marshals plain Ruby values (simple attributes), numbers come back as BigDecimal.
module Dynamo
  module_function

  def client_options
    options = { region: ENV.fetch("AWS_REGION", "us-east-1") }
    options[:endpoint] = ENV["AWS_ENDPOINT_URL"] if ENV["AWS_ENDPOINT_URL"].present?
    options
  end

  def client
    @client ||= Aws::DynamoDB::Client.new(client_options)
  end

  def reset!
    @client = nil
  end

  def table(name)
    Schema.table_name(name)
  end

  # Normalizes values read back from DynamoDB (BigDecimal -> Integer).
  def plain(value)
    case value
    when BigDecimal then value.frac.zero? ? value.to_i : value.to_f
    when Hash       then value.transform_values { |v| plain(v) }
    when Array      then value.map { |v| plain(v) }
    else value
    end
  end

  def now_iso
    Time.now.utc.iso8601(6)
  end

  # Runs every page of a query/scan and returns all the items.
  def paginate(operation, **params)
    items = []
    loop do
      response = client.public_send(operation, **params)
      items.concat(response.items)
      break if response.last_evaluated_key.blank?

      params = params.merge(exclusive_start_key: response.last_evaluated_key)
    end
    items.map { |item| plain(item) }
  end

  def cancellation_codes(error)
    error.cancellation_reasons.map(&:code)
  end
end
