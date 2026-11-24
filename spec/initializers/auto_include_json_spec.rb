require "rails_helper"

RSpec.describe "AutoIncludeJson monkey patch" do
  let!(:user) { User.create!(email: "test@example.com", encrypted_password: BCrypt::Password.create("password")) }
  let!(:role1) { Role.create!(name: "Admin") }
  let!(:role2) { Role.create!(name: "Manager") }

  before do
    user.roles << role1
    user.roles << role2
  end

  let(:json_attrs) do
    {
      except: [:lock_version, :updated_at, :encrypted_password],
      include: { roles: { only: [:id, :name] } }
    }
  end

  describe "User#to_json with includes" do
    it "returns valid JSON with associations included" do
      json = User.where(id: user.id).first.to_json(json_attrs)
      parsed = JSON.parse(json)
      expect(parsed).to have_key("roles")
      expect(parsed["roles"].size).to eq(2)
      expect(parsed["roles"].map { |r| r["name"] }).to match_array(%w[Admin Manager])
    end
  end

  # Rails 8.1's JSON encoder hands as_json a frozen options hash; json_attrs is shared per model.
  describe "User#as_json with frozen options" do
    it "serializes the includes and leaves the caller's options untouched" do
      options = json_attrs.deep_dup.freeze
      parsed = user.reload.as_json(options)
      expect(parsed["roles"].map { |r| r["name"] }).to match_array(%w[Admin Manager])
      expect(options).to eq(json_attrs)
    end
  end

  describe "User.all.to_json with includes" do
    it "eager loads associations and serializes cleanly" do
      json = User.all.to_json(json_attrs)
      parsed = JSON.parse(json)
      user_json = parsed.find { |u| u["id"] == user.id }
      expect(user_json).to have_key("roles")
      expect(user_json["roles"].size).to eq(2)
    end
  end
end
