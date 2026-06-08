class Api::V3::UsersController < Api::V3::ApplicationController
  before_action :check_demoting, only: [ :update, :patch, :destroy ]

  private

  def check_demoting
    attrs = (params.dig("data", "attributes") || {})
    unauthorized! StandardError.new("You cannot demote yourself") if (params[:id].to_i == current_user.id && (attrs.key?("admin") || attrs.key?("locked")))
  end
end
