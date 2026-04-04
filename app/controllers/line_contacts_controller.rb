class LineContactsController < ApplicationController
  before_action :require_admin
  before_action :set_line_contact, only: %i[show create_user]

  def index
    @line_contacts = LineContact.recent
  end

  def show
  end

  # GET /line_contacts/:id/new_user — form to create a user and link
  def new_user
    @line_contact = LineContact.find(params[:id])
    @generated_password = SecureRandom.alphanumeric(16)
    @user = User.new(
      name: @line_contact.display_name,
      role: "viewer"
    )
  end

  # POST /line_contacts/:id/create_user — create user, link LINE, delete contact
  def create_user
    @user = User.new(user_params)
    @user.provider = "line"
    @user.uid = @line_contact.line_user_id
    @user.llm_consent = true

    if @user.save
      # Optionally notify the user via LINE push
      Line::ReplyService.push(@line_contact.line_user_id, "Your account is now set up! You can start chatting.") rescue nil
      @line_contact.destroy!
      redirect_to chat_messages_path, notice: "User #{@user.name} created and linked to LINE."
    else
      render :new_user, status: :unprocessable_entity
    end
  end

  private

  def set_line_contact
    @line_contact = LineContact.find(params[:id])
  end

  def require_admin
    unless current_user.admin?
      redirect_to root_path, alert: "Only admins can access LINE contacts."
    end
  end

  def user_params
    params.require(:user).permit(:username, :email, :name, :password, :password_confirmation, :role)
  end
end
