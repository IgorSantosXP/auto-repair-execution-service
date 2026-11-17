module Messaging
  module Handlers
    REGISTRY = {
      "execution.start" => Handlers::StartExecution
    }.freeze
  end
end
