class Api::V2::UsersController < Api::V2::ApplicationController #Api::V2::BaseController
  # # CanCanCan
  # load_and_authorize_resource
  # before_action :authenticate_user!
  before_action :check_demoting, only: [ :update, :destroy ]
  
  def index
    render json: { prova: true }, status: 200
  end
  
  private
  
  def check_demoting
    render json: "You cannot demote yourself", status: 403 if (params[:id].to_i == current_user.id && (params[:user].keys.include?("admin") || params[:user].keys.include?("locked")))
  end
  
  def request_params
    params.require(:user).permit!.delete_if{ |_,v| v.nil? }
  end
end
