require "rails_helper"

# A model can declare a creation key (`self.creation_key`): the columns that identify a
# record its client generated. A POST whose key matches an existing record is a repeat of
# a creation that already happened (a client resending after a lost response), so it
# returns that record instead of creating a copy.
RSpec.describe "API v2 create with a creation key", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers_for(user) }

  around do |example|
    Role.define_singleton_method(:creation_key) { %i[name] }
    example.run
  ensure
    Role.singleton_class.send(:remove_method, :creation_key)
  end

  def post_role(name)
    post "/api/v2/roles", params: { role: { name: name } }.to_json, headers: headers
  end

  it "returns the existing record with 200 when the key already exists, creating nothing" do
    post_role("planner")
    expect(response).to have_http_status(:created)
    first_id = JSON.parse(response.body)["id"]

    expect { post_role("planner") }.not_to change(Role, :count)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["id"]).to eq(first_id)
  end

  it "ignores the repeated request's body: the existing record is returned unchanged" do
    LdapServer.define_singleton_method(:creation_key) { %i[host] }
    existing = LdapServer.create!(host: "ldap.example", base_dn: "dc=first")

    expect {
      post "/api/v2/ldap_servers", params: {ldap_server: {host: "ldap.example", base_dn: "dc=stale"}}.to_json,
        headers: headers
    }.not_to change(LdapServer, :count)

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["base_dn"]).to eq("dc=first")
    expect(existing.reload.base_dn).to eq("dc=first")
  ensure
    LdapServer.singleton_class.send(:remove_method, :creation_key)
  end

  it "returns the existing record with 200 when a racing request inserted it after the check" do
    existing = create(:role, name: "planner")
    lookups = 0
    # The racing request commits between this request's lookup and its insert: the lookup
    # sees nothing, the insert trips the unique index.
    allow(Role).to receive(:find_by).and_wrap_original do |original, *args|
      lookups += 1
      lookups == 1 ? nil : original.call(*args)
    end

    expect { post_role("planner") }.not_to change(Role, :count)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["id"]).to eq(existing.id)
  end

  it "refuses with 403, creating nothing, when the caller cannot read the existing record" do
    create(:role, name: "planner")
    ability = Object.new.extend(CanCan::Ability)
    ability.can :create, Role
    allow(Ability).to receive(:new).and_return(ability)

    # ApiExceptionManagement maps AccessDenied to 403 in production only; here the
    # exception itself is the observable outcome, so let it reach the test.
    allow(Rails.application).to receive(:env_config)
      .and_return(Rails.application.env_config.merge("action_dispatch.show_exceptions" => :none))

    expect { post_role("planner") }.to raise_error(CanCan::AccessDenied)
    expect(Role.count).to eq(1)
  end
end
