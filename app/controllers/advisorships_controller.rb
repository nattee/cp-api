class AdvisorshipsController < ApplicationController
  before_action :require_admin
  before_action :set_advisorship, only: %i[update destroy]

  def create
    advisorship = Advisorship.new(advisorship_params)
    if advisorship.save
      redirect_to advisorship.student, notice: "Advisor added."
    else
      redirect_to advisorship.student || students_path, alert: advisorship.errors.full_messages.to_sentence
    end
  end

  # The only edit is ending: sets ended_on, preserving history. Reassignment
  # is end + create, never destroy.
  def update
    if @advisorship.update(ended_on: Date.current)
      redirect_to @advisorship.student, notice: "Advisorship ended."
    else
      redirect_to @advisorship.student, alert: @advisorship.errors.full_messages.to_sentence
    end
  end

  # Destroy is for mistakes only (wrong person clicked in).
  def destroy
    student = @advisorship.student
    @advisorship.destroy!
    redirect_to student, notice: "Advisorship removed."
  end

  private

  def set_advisorship
    @advisorship = Advisorship.find(params[:id])
  end

  def advisorship_params
    params.require(:advisorship).permit(:student_id, :staff_id, :started_on, :note)
  end
end
