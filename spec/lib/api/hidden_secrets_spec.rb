require "rails_helper"

# Api::HiddenSecrets: the secret-named columns a model already hides somehow (host Odoo #6313).
RSpec.describe Api::HiddenSecrets do
  # Subclassing a model runs thecore's default-module registry, which rewrites the json_attrs
  # class variable the subclass shares with its parent: put it back.
  around do |example|
    saved = UsedToken.json_attrs
    example.run
  ensure
    UsedToken.json_attrs = saved
  end

  let(:token_hidden_by_json_attrs) do
    Class.new(UsedToken) do
      def self.name = "UsedToken"
      def self.json_attrs = {except: [:token]}
    end
  end

  it "are the secrets Devise leaves out of the default JSON, not its sign-in tracking" do
    expect(described_class.for(User)).to eq(["encrypted_password"])
  end

  it "include write_only_attributes" do
    expect(described_class.for(LdapServer)).to include("admin_password")
  end

  it "include a secret the model excepts in its own json_attrs" do
    expect(described_class.for(token_hidden_by_json_attrs)).to eq(["token"])
  end

  it "leave out a secret-named column the model does not hide, which stays ransackable" do
    expect(described_class.for(UsedToken)).to eq([])
    expect(UsedToken.ransackable_attributes).to include("token")
  end

  it "are not ransackable" do
    expect(User.ransackable_attributes).not_to include("encrypted_password")
    expect(User.ransackable_attributes).to include("email", "sign_in_count")
    expect(LdapServer.ransackable_attributes).not_to include("admin_password")
  end

  it "are refused to v2 request options too" do
    record = token_hidden_by_json_attrs.find(UsedToken.create!(user: create(:user), token: "t-123").id)

    expect(record.as_json(Api::V2::RequestJsonAttrs.from_params(only: %w[id token]))).to eq("id" => record.id)
    expect(UsedToken.find(record.id).as_json(Api::V2::RequestJsonAttrs.from_params(only: %w[token])))
      .to eq("token" => "t-123")
  end
end
