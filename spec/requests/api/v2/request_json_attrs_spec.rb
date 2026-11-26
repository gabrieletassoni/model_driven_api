require "rails_helper"

# The serialization options a client sends in the query string (`a`, alias `json_attrs`) follow
# the security conventions of host Odoo #6285: they can read what a developer exposed, never run
# a side effect nobody exposed, never bring back an attribute the model hides. A rejected name is
# dropped and the response stays 200.
RSpec.describe "API v2 serialization options from the request", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers_for(user) }
  let!(:role) { create(:role, name: "Reader") }

  def body = JSON.parse(response.body)

  it "never runs destroy named in a[methods]" do
    get "/api/v2/roles/#{role.id}", params: { a: { only: %w[id], methods: %w[destroy] } }, headers: headers

    expect(response).to have_http_status(:ok)
    expect(body).to eq("id" => role.id)
    expect(Role.exists?(role.id)).to be(true)
  end

  it "never runs destroy named as an include" do
    get "/api/v2/roles/#{role.id}", params: { a: { only: %w[id], include: { destroy: { only: %w[id] } } } }, headers: headers

    expect(response).to have_http_status(:ok)
    expect(body).to eq("id" => role.id)
    expect(Role.exists?(role.id)).to be(true)
  end

  it "never runs destroy from the index either" do
    get "/api/v2/roles", params: { a: { only: %w[id], methods: %w[destroy] } }, headers: headers

    expect(response).to have_http_status(:ok)
    expect(body).to eq([{ "id" => role.id }])
    expect(Role.count).to eq(1)
  end

  it "does not serve framework methods such as attributes" do
    get "/api/v2/users/#{user.id}", params: { a: { only: %w[id], methods: %w[attributes] } }, headers: headers

    expect(response).to have_http_status(:ok)
    expect(body).to eq("id" => user.id)
  end

  it "still serves columns and real associations the client asks for" do
    user.roles << role
    get "/api/v2/users/#{user.id}", params: { a: { only: %w[id email], include: { roles: { only: %w[name] } } } },
                                    headers: headers

    expect(body).to eq("id" => user.id, "email" => user.email, "roles" => [{ "name" => "Reader" }])
  end

  it "applies the same rules to the record an update renders" do
    put "/api/v2/roles/#{role.id}", params: { role: { name: "Editor" }, a: { only: %w[id name], methods: %w[destroy] } },
                                    headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(body).to eq("id" => role.id, "name" => "Editor")
    expect(Role.exists?(role.id)).to be(true)
  end
end
