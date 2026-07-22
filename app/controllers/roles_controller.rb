class RolesController < ApplicationController
  # Entirely admin-only: role bundles decide who sees what, so even reading
  # them is an administration concern.
  before_action :require_admin
  before_action :set_role, only: %i[show edit update destroy]

  def index
    # Tiny table (a handful of roles) — eager-load and count in Ruby rather
    # than a grouped select, which trips up relation#empty? in the view.
    @roles = Role.includes(:parent_roles, :users).order(:name)
  end

  def show
  end

  def new
    @role = Role.new
  end

  def create
    @role = Role.new(role_params)

    if @role.save
      redirect_to @role, notice: "Role was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid => e
    @role.errors.add(:base, e.record.errors.full_messages.to_sentence)
    render :new, status: :unprocessable_entity
  end

  def edit
  end

  def update
    if @role.update(role_params)
      redirect_to @role, notice: "Role was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid => e
    # parent_role_ids= on a persisted record saves edges immediately; a cycle
    # or locked-role rejection surfaces as RecordInvalid, not a false update.
    @role.errors.add(:base, e.record.errors.full_messages.to_sentence)
    render :edit, status: :unprocessable_entity
  end

  def destroy
    if @role.destroy
      redirect_to roles_path, notice: "Role was successfully deleted."
    else
      redirect_to @role, alert: @role.errors.full_messages.to_sentence
    end
  end

  private

  def set_role
    @role = Role.find(params[:id])
  end

  def role_params
    permitted = params.require(:role).permit(:name, :description, permission_keys: [], parent_role_ids: [])
    permitted[:permission_keys] = Array(permitted[:permission_keys]).reject(&:blank?) if permitted.key?(:permission_keys)
    permitted[:parent_role_ids] = Array(permitted[:parent_role_ids]).reject(&:blank?) if permitted.key?(:parent_role_ids)
    permitted
  end
end
