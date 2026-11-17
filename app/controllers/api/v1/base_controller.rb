module Api
  module V1
    class BaseController < ApplicationController
      before_action :authenticate_admin!

      private

      # This service only verifies the token issued by the OS service; it has no user table.
      def authenticate_admin!
        token = request.headers["Authorization"]&.split(" ")&.last
        raise JWT::DecodeError, "Missing token" if token.blank?

        @current_admin_id = Identity::Services::JwtEncoder.decode(token)["sub"]
      rescue JWT::DecodeError
        render_error(code: "unauthorized", message: "Invalid or expired token", status: :unauthorized)
      end

      def render_not_found(message)
        render_error(code: "not_found", message: message, status: :not_found)
      end

      # Use cases return either plain messages (validation) or {code:, message:} hashes.
      def render_failure(result)
        error = result.errors.first
        return render_result(result) unless error.is_a?(Hash)

        status = error[:code] == "not_found" ? :not_found : :unprocessable_entity
        render_error(code: error[:code], message: error[:message], details: error[:details], status: status)
      end
    end
  end
end
