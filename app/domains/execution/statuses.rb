module Execution
  module Statuses
    QUEUED       = "queued".freeze
    IN_DIAGNOSIS = "in_diagnosis".freeze
    IN_REPAIR    = "in_repair".freeze
    FINISHED     = "finished".freeze

    ALL   = [ QUEUED, IN_DIAGNOSIS, IN_REPAIR, FINISHED ].freeze
    QUEUE = [ IN_REPAIR, IN_DIAGNOSIS, QUEUED ].freeze # display priority

    # action => [from, to, event published to the OS service]
    TRANSITIONS = {
      "start_diagnosis" => [ QUEUED, IN_DIAGNOSIS, "execution.diagnosis_started" ],
      "start_repair"    => [ IN_DIAGNOSIS, IN_REPAIR, "execution.repair_started" ],
      "finish"          => [ IN_REPAIR, FINISHED, "execution.finished" ]
    }.freeze

    def self.next_action(status)
      TRANSITIONS.find { |_, (from, _, _)| from == status }&.first
    end
  end
end
