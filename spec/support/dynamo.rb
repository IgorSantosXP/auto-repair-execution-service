RSpec.configure do |config|
  config.before(:suite) do
    Dynamo::Provisioner.new.call
    Dynamo::Testing.clean!
  end

  config.before { Dynamo::Testing.clean! if Dynamo::Testing.dirty? }
  config.after  { Dynamo::Testing.mark_dirty! }
end

module Dynamo
  # Wipes every table between examples (the tables themselves are created once per run).
  module Testing
    module_function

    def mark_dirty!
      @dirty = true
    end

    def dirty?
      @dirty != false
    end

    def clean!
      Schema::TABLES.each do |name, definition|
        table = Schema.table_name(name)
        keys  = definition[:key_schema].map(&:first)
        Dynamo.paginate(:scan, table_name: table).each do |item|
          Dynamo.client.delete_item(table_name: table, key: item.slice(*keys))
        end
      end
      @dirty = false
    end
  end
end
