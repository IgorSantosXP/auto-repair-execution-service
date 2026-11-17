# Local development only: creates the DynamoDB tables when the web server boots.
# The worker provisions them in `messaging:work`; on AWS Terraform owns the tables.
if ENV["DYNAMODB_AUTO_PROVISION"] == "true" && !Rails.env.test?
  Rails.application.config.after_initialize do
    Dynamo::Provisioner.new.call if defined?(Rails::Server)
  end
end
