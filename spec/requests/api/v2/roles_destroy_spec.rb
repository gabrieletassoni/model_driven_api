require "rails_helper"

RSpec.describe "API v2 Roles destroy error handling", type: :request do
  let(:user) { create(:user) }
  let(:headers) { auth_headers_for(user) }
  let!(:role) { create(:role) }

  describe "DELETE /api/v2/roles/:id when destroy is blocked" do
    before do
      allow_any_instance_of(Role).to receive(:destroy) do |record|
        record.errors.add(:base, "cannot delete: has dependent records")
        false
      end
    end

    it "returns HTTP 422 instead of a bare 500" do
      delete "/api/v2/roles/#{role.id}", headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "includes the validation error message in the response body" do
      delete "/api/v2/roles/#{role.id}", headers: headers
      json = JSON.parse(response.body)
      expect(json["error"]).to include("cannot delete: has dependent records")
    end

    it "does not destroy the record" do
      expect {
        delete "/api/v2/roles/#{role.id}", headers: headers
      }.not_to change(Role, :count)
    end
  end

  describe "DELETE /api/v2/roles/:id when destroy succeeds" do
    it "returns HTTP 200" do
      delete "/api/v2/roles/#{role.id}", headers: headers
      expect(response).to have_http_status(:ok)
    end

    it "destroys the record" do
      expect {
        delete "/api/v2/roles/#{role.id}", headers: headers
      }.to change(Role, :count).by(-1)
    end
  end
end
