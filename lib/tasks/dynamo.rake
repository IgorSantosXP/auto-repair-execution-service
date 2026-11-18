namespace :dynamo do
  desc "Creates the DynamoDB tables (idempotent)"
  task setup: :environment do
    Dynamo::Provisioner.new.call
    puts "DynamoDB tables ready (prefix #{Dynamo::Schema.prefix})"
  end

  # On AWS the tables come from Terraform and the pod's IAM role cannot create
  # them, so the seed only provisions when running locally.
  desc "Loads the demo parts (idempotent)"
  task seed: :environment do
    Rake::Task["dynamo:setup"].invoke if ENV["DYNAMODB_AUTO_PROVISION"] == "true"
    load Rails.root.join("db/seeds.rb")
  end
end
