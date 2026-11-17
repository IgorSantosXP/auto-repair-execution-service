require "rails_helper"

RSpec.configure do |config|
  config.openapi_root = Rails.root.to_s + "/swagger"

  config.openapi_specs = {
    "v1/swagger.yaml" => {
      openapi: "3.0.1",
      info: {
        title: "Execution Service",
        version: "v1",
        description: "Fila de execução das ordens de serviço e catálogo de peças/estoque (DynamoDB)"
      },
      paths: {},
      components: {
        securitySchemes: {
          bearerAuth: { type: :http, scheme: :bearer, bearerFormat: "JWT" }
        },
        schemas: {}
      },
      servers: [ { url: "/", description: "Current host" } ]
    }
  }

  config.openapi_format = :yaml
end
