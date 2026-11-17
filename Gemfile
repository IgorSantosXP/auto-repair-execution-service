source "https://rubygems.org"

gem "rails", "~> 8.1.3", ">= 8.1.3.1"
gem "puma", ">= 5.0"

gem "tzinfo-data", platforms: %i[ windows jruby ]

gem "bootsnap", require: false
gem "thruster", require: false

gem "jwt"

gem "rswag-api"
gem "rswag-ui"

gem "datadog", "~> 2.3"
gem "dogstatsd-ruby", "~> 5.6"
gem "lograge"

gem "aws-sdk-dynamodb"
gem "aws-sdk-sns"
gem "aws-sdk-sqs"

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "bundler-audit", require: false
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
  gem "rspec-rails"
  gem "faker"
  gem "rswag-specs"
  gem "simplecov", require: false
  gem "webmock"
  gem "cucumber", require: false
  gem "rack-test", require: false
end
