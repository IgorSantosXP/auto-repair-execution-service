require "rails_helper"

RSpec.describe Identity::Services::JwtEncoder do
  it "round-trips admin tokens and rejects customer tokens" do
    token = described_class.encode({ "sub" => "7" })

    expect(described_class.decode(token)["sub"]).to eq("7")
    expect { described_class.decode(token, audience: "customer") }.to raise_error(JWT::DecodeError)
  end
end

RSpec.describe Result do
  it "wraps success and failure" do
    expect(described_class.success(payload: 1)).to be_success
    expect(described_class.failure(errors: "x").errors).to eq([ "x" ])
  end
end
