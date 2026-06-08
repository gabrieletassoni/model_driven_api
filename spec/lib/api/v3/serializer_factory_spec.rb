require "rails_helper"

RSpec.describe Api::V3::SerializerFactory do
  describe ".serializer_for" do
    subject(:serializer_class) { described_class.serializer_for(Role) }

    it "returns a class" do
      expect(serializer_class).to be_a(Class)
    end

    it "assigns a named constant Api::V3::RoleSerializer" do
      described_class.serializer_for(Role)
      expect(defined?(Api::V3::RoleSerializer)).to eq("constant")
    end

    it "returns the same class on repeated calls (memoized)" do
      first = described_class.serializer_for(Role)
      second = described_class.serializer_for(Role)
      expect(first).to equal(second)
    end

    it "generates a class that includes JSONAPI::Serializer" do
      expect(serializer_class.ancestors).to include(JSONAPI::Serializer)
    end

    it "serializes a record into a JSON:API data envelope" do
      role = Role.new(id: 1, name: "Admin")
      result = serializer_class.new(role).serializable_hash
      expect(result[:data][:type]).to eq(:roles)
      expect(result[:data][:attributes]).to include(name: "Admin")
    end

    it "derives attributes from json_attrs except: when only: is absent" do
      role = Role.new(id: 1, name: "Admin")
      result = serializer_class.new(role).serializable_hash
      attrs = result[:data][:attributes].keys.map(&:to_s)
      expect(attrs).to include("name")
      expect(attrs).not_to include("lock_version", "created_at", "updated_at", "id")
    end

    context "with include: in json_attrs" do
      it "declares a has_many :users relationship on the serializer" do
        # ModelDrivenApiRole sets include: [users: { only: [:id] }]
        expect(serializer_class.relationships_to_serialize).to have_key(:users)
      end

      it "caches the nested serializer as UserForRoleSerializer" do
        described_class.serializer_for(Role)
        expect(defined?(Api::V3::UserForRoleSerializer)).to eq("constant")
      end

      it "includes relationship linkage in the serialized output" do
        role = Role.create!(name: "Admin")
        user = User.create!(email: "rel@example.com", encrypted_password: BCrypt::Password.create("x"))
        role.users << user

        result = serializer_class.new(role, include: [:users]).serializable_hash
        expect(result[:data][:relationships]).to have_key(:users)
        user_ids = result[:data][:relationships][:users][:data].map { |d| d[:id] }
        expect(user_ids).to include(user.id.to_s)
      end

      it "sideloads users in the included array when include: [:users] is passed" do
        role = Role.create!(name: "Admin")
        user = User.create!(email: "side@example.com", encrypted_password: BCrypt::Password.create("x"))
        role.users << user

        result = serializer_class.new(role, include: [:users]).serializable_hash
        expect(result[:included]).to be_an(Array)
        expect(result[:included].first[:type]).to eq(:users)
      end

      it "sideloaded users have only the attributes from the nested spec (only: [:id])" do
        role = Role.create!(name: "Admin")
        user = User.create!(email: "spec@example.com", encrypted_password: BCrypt::Password.create("x"))
        role.users << user

        result = serializer_class.new(role, include: [:users]).serializable_hash
        included_user = result[:included].first
        # only: [:id] → id is the JSON:API id field; attributes key is absent or empty
        expect(included_user[:attributes].to_h).to be_empty
      end
    end

    context "with methods: in json_attrs" do
      let(:model_stub) do
        stub_const("StubModel", Class.new do
          def self.json_attrs = { methods: [:greeting] }
          def self.column_names = ["id"]
          def self.reflect_on_all_associations = []
          def self.model_name = ActiveModel::Name.new(self, nil, "stub_model")
          include ActiveModel::Model
          attr_accessor :id
          def greeting = "hello"
        end)
        StubModel
      end

      it "generates a block-form attribute for each method" do
        serializer = described_class.serializer_for(model_stub)
        instance = model_stub.new(id: 1)
        result = serializer.new(instance).serializable_hash
        expect(result[:data][:attributes]).to include(greeting: "hello")
      end
    end

    context "when a host app defines Api::V3::RoleSerializer explicitly" do
      before do
        stub_const("Api::V3::RoleSerializer", Class.new do
          include JSONAPI::Serializer
          attributes :name
        end)
      end

      it "returns the explicit class without overriding it" do
        result = described_class.serializer_for(Role)
        expect(result).to eq(Api::V3::RoleSerializer)
      end
    end
  end

  describe ".extract_includes" do
    it "returns empty hash for nil" do
      expect(described_class.extract_includes(nil)).to eq({})
    end

    it "maps symbol items to key => nil" do
      expect(described_class.extract_includes([:roles])).to eq({ roles: nil })
    end

    it "maps hash items to key => spec" do
      spec = { only: [:id] }
      expect(described_class.extract_includes([users: spec])).to eq({ users: spec })
    end

    it "handles mixed symbol and hash items" do
      result = described_class.extract_includes([:roles, { users: { only: [:id] } }])
      expect(result).to eq({ roles: nil, users: { only: [:id] } })
    end
  end
end
