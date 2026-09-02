require "rails_helper"

# Covers the default `json_attrs` module registered into
# ThecoreBackendCommons::DefaultModuleRegistry (ADR 0001, issue #5) --
# distinct from spec/initializers/auto_include_json_spec.rb, which covers the
# unrelated AutoIncludeJson `to_json(include:)` cascading monkeypatch.
RSpec.describe "Default json_attrs (DefaultModuleRegistry)" do
  describe "a dummy-app model with no explicit Api::ModelName concern" do
    it "gets the generic default module included" do
      expect(RoleUser.include?(ModelDrivenApiDefaultJsonAttrs)).to be true
    end

    it "responds to .json_attrs with the sensible default (all columns, no methods, no associations)" do
      expect(RoleUser.json_attrs).to eq(except: [])
    end

    it "lands json_attrs as an *own* method, satisfying the info_controller's instance_methods(false) check" do
      expect(RoleUser.instance_methods(false)).to include(:json_attrs)
    end
  end

  describe "a dummy-app model with an explicit concern (Role, via ModelDrivenApiRole)" do
    it "keeps its customized json_attrs -- the default does not clobber or survive underneath it" do
      expect(Role.json_attrs[:except]).to contain_exactly(:lock_version, :created_at, :updated_at)
      expect(Role.json_attrs[:include]).to eq([users: {only: [:id]}])
      expect(Role.json_attrs).not_to eq(except: [])
    end

    it "still lands json_attrs as an own method" do
      expect(Role.instance_methods(false)).to include(:json_attrs)
    end
  end

  describe "abstract/STI exclusion" do
    it "ApplicationRecord itself never receives the default (abstract_class)" do
      expect(ApplicationRecord.abstract_class?).to be true
      expect(ApplicationRecord.include?(ModelDrivenApiDefaultJsonAttrs)).to be false
    end
  end

  describe "GET /api/v2/info/schema and /api/v2/info/dsl", type: :request do
    let(:user) { create(:user) }
    let(:role) { create(:role) }
    let(:headers) { auth_headers_for(user) }

    before do
      # Ensure RoleUser (the no-explicit-concern fixture above) is actually
      # loaded/autoloaded and has at least one row before hitting either
      # endpoint -- ApplicationRecord.subclasses only reflects classes that
      # have already been referenced, and these actions walk that list.
      RoleUser.create!(role: role, user: user)
    end

    it "/schema includes the default-only model, with its columns introspected" do
      get "/api/v2/info/schema", headers: headers
      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      expect(json).to have_key("role_users")
      expect(json["role_users"]).to have_key("created_at")
      expect(json["role_users"]["associations"]["belongs_to"]).to match_array(%w[role user])
      expect(json["role_users"]).to have_key("methods")
      expect(json["role_users"]["methods"]).to be_nil
    end

    it "/dsl exposes the resolved default json_attrs for the default-only model -- not nil" do
      get "/api/v2/info/dsl", headers: headers
      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      expect(json).to have_key("role_users")
      expect(json["role_users"]).to eq("except" => [])
    end

    it "/dsl still exposes Role's customized json_attrs unaffected by the default" do
      get "/api/v2/info/dsl", headers: headers
      json = JSON.parse(response.body)

      expect(json["roles"]).not_to be_nil
      expect(json["roles"]["except"]).to match_array(%w[lock_version created_at updated_at])
      expect(json["roles"]["include"]).to eq([{"users" => {"only" => ["id"]}}])
    end
  end
end
