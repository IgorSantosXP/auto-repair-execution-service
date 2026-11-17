require "datadog"
require "datadog/statsd"

# Without an agent (local development and tests) tracing stays off, otherwise the
# tracer keeps trying to flush to a non-existent agent and floods the logs.
unless ENV["DD_AGENT_HOST"].present?
  Datadog.configure { |c| c.tracing.enabled = false }
  return
end

Datadog.configure do |c|
  c.service = ENV.fetch("DD_SERVICE", "execution-service")
  c.env     = ENV.fetch("DD_ENV", Rails.env)
  c.version = ENV.fetch("DD_VERSION", "unknown")

  c.agent.host = ENV.fetch("DD_AGENT_HOST")
  c.agent.port = ENV.fetch("DD_TRACE_AGENT_PORT", "8126").to_i

  c.tracing.enabled = true
  c.tracing.instrument :rails, service_name: ENV.fetch("DD_SERVICE", "execution-service")
  c.tracing.instrument :active_support

  c.runtime_metrics.enabled = true
end
