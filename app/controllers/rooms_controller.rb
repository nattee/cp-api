class RoomsController < ApplicationController
  before_action :set_room, only: %i[edit update destroy]
  before_action :require_admin, only: %i[new create edit update destroy]

  def index
    @rooms = Room.order(:building, :room_number)
  end

  def new
    @room = Room.new
  end

  def create
    @room = Room.new(room_params)
    if @room.save
      redirect_to rooms_path, notice: "Room was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @room.update(room_params)
      redirect_to rooms_path, notice: "Room was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @room.destroy
      redirect_to rooms_path, notice: "Room was successfully deleted."
    else
      redirect_to rooms_path, alert: @room.errors.full_messages.to_sentence
    end
  end

  private

  def set_room
    @room = Room.find(params[:id])
  end

  def require_admin
    unless current_user.admin?
      redirect_to rooms_path, alert: "Only admins can perform this action."
    end
  end

  def room_params
    params.require(:room).permit(:building, :room_number, :room_type, :capacity)
  end
end
