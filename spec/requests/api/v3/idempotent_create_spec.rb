require "rails_helper"

# Same creation-key contract as v2 (spec/requests/api/v2/idempotent_create_spec.rb), with
# JSON:API envelopes.
RSpec.describe "API v3 create with a creation key", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers_for(user) }

  around do |example|
    Role.define_singleton_method(:creation_key) { %i[name] }
    example.run
  ensure
    Role.singleton_class.send(:remove_method, :creation_key)
  end

  def post_role(name)
    post "/api/v3/roles", params: { data: { type: "roles", attributes: { name: name } } }.to_json, headers: headers
  end

  it "returns the existing resource with 200 when the key already exists, creating nothing" do
    existing = create(:role, name: "planner")

    expect { post_role("planner") }.not_to change(Role, :count)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["data"]["id"]).to eq(existing.id.to_s)
  end
end
