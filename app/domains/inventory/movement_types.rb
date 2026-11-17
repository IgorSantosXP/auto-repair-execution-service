module Inventory
  module MovementTypes
    CREDIT = %w[inbound adjustment_in].freeze
    DEBIT  = %w[outbound adjustment_out].freeze
    MANUAL = (CREDIT + DEBIT).freeze            # accepted by the API
    ALL    = (MANUAL + %w[reservation release]).freeze # reservation/release come from the saga
  end
end
