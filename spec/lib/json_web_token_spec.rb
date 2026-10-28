require "rails_helper"

RSpec.describe JsonWebToken do
  let(:previous_key) { "p" * 64 }

  around do |example|
    saved = ENV.to_h.slice("SECRET_KEY_BASE_PREVIOUS", "SECRET_KEY_BASE_PREVIOUS_EXPIRES_AT")
    ENV["SECRET_KEY_BASE_PREVIOUS"] = previous_key
    ENV["SECRET_KEY_BASE_PREVIOUS_EXPIRES_AT"] = 1.hour.from_now.utc.iso8601
    example.run
  ensure
    ENV.delete("SECRET_KEY_BASE_PREVIOUS")
    ENV.delete("SECRET_KEY_BASE_PREVIOUS_EXPIRES_AT")
    ENV.update(saved)
  end

  def token(key, exp: 30.minutes.from_now)
    JWT.encode({ user_id: 7, exp: exp.to_i }, key)
  end

  it "decodes a token it encoded" do
    expect(described_class.decode(described_class.encode(user_id: 7))[:user_id]).to eq(7)
  end

  it "signs new tokens with the current key, never the previous one" do
    expect { JWT.decode(described_class.encode(user_id: 7), previous_key) }.to raise_error(JWT::VerificationError)
  end

  it "rejects a token signed with neither key" do
    expect { described_class.decode(token("x" * 64)) }.to raise_error(JWT::VerificationError)
  end

  it "does not let the previous key revive an expired token" do
    expect { described_class.decode(token(previous_key, exp: 1.minute.ago)) }.to raise_error(JWT::ExpiredSignature)
  end

  it "rejects a previous-key token when the window end is not a time" do
    ENV["SECRET_KEY_BASE_PREVIOUS_EXPIRES_AT"] = "tomorrow"
    expect { described_class.decode(token(previous_key)) }.to raise_error(JWT::VerificationError)
  end
end
