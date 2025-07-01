require 'rails_helper'

RSpec.describe 'AutoIncludeJson monkey patch' do
  let!(:plant) { Plant.create!(name: 'Plant 1', code: 'PL1', printer_id: 123) }
  let!(:user) { User.create!(name: 'Test User', plant: plant) }
  let!(:role1) { user.roles.create!(name: 'Admin') }
  let!(:role2) { user.roles.create!(name: 'Manager') }

  let(:json_attrs) do
    {
      except: [:lock_version, :updated_at, :encrypted_access_token, :access_token],
      include: [
        :roles,
        plant: {
          only: [:id, :name, :code, :printer_id]
        }
      ]
    }
  end

  describe 'User#to_json with includes' do
    it 'returns valid JSON with associations included and no N+1' do
      # Prevent N+1 queries via ActiveRecord::QueryRecorder
      expect {
        json = User.where(id: user.id).first.to_json(json_attrs)
        parsed = JSON.parse(json)
        expect(parsed).to include('roles', 'plant')
        expect(parsed['roles'].size).to eq(2)
        expect(parsed['plant']['code']).to eq('PL1')
      }.not_to exceed_query_limit(2) # One for user, one for preloaded associations
    end
  end

  describe 'User.all.to_json with includes' do
    it 'eager loads associations and serializes cleanly' do
      expect {
        json = User.all.to_json(json_attrs)
        parsed = JSON.parse(json)
        expect(parsed.first).to include('roles', 'plant')
        expect(parsed.first['plant']['code']).to eq('PL1')
      }.not_to exceed_query_limit(2)
    end
  end
end
