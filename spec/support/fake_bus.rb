class FakeBus
  attr_reader :published

  def initialize
    @published = []
  end

  def publish(envelope)
    @published << envelope
  end

  def types
    @published.map(&:type)
  end
end

RSpec.configure do |config|
  config.before do
    @fake_bus = FakeBus.new
    Messaging.bus = @fake_bus
    Messaging.logger = Messaging::JsonLogger.new(StringIO.new)
  end

  config.after { Messaging.reset! }
end
