namespace :dynamo do
  desc "Creates the DynamoDB tables (idempotent)"
  task setup: :environment do
    Dynamo::Provisioner.new.call
    puts "DynamoDB tables ready (prefix #{Dynamo::Schema.prefix})"
  end

  desc "Loads the demo parts (idempotent)"
  task seed: :setup do
    load Rails.root.join("db/seeds.rb")
  end
end
