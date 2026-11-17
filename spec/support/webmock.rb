require "webmock/rspec"

WebMock.disable_net_connect!(allow: [ "localstack", "localhost", "127.0.0.1" ])
