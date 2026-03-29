class SchedulesController < ApplicationController
  def index
  end

  def room
    @semesters = Semester.ordered
    @rooms = Room.order(:building, :room_number)

    if params[:semester_id].present? && params[:room_id].present?
      @semester = Semester.find(params[:semester_id])
      @room = Room.find(params[:room_id])

      time_slots = TimeSlot.joins(section: { course_offering: :course })
                           .where(room: @room, course_offerings: { semester: @semester })
                           .includes(section: [:teachings => :staff, course_offering: :course])

      @entries = time_slots.map do |ts|
        staff_names = ts.section.teachings.map { |t| t.staff.display_name_th }.join(", ")
        {
          day_of_week: ts.day_of_week,
          start_time: ts.start_time.strftime("%H:%M"),
          end_time: ts.end_time.strftime("%H:%M"),
          label: ts.section.course_offering.course.course_no,
          sublabel: "Sec #{ts.section.section_number}",
          detail: staff_names.presence,
          color_key: ts.section.course_offering.course.course_no,
          url: course_offering_path(ts.section.course_offering)
        }
      end
    end
  end

  def staff
    @semesters = Semester.ordered
    @staffs = Staff.active.order(:first_name, :last_name)

    if params[:semester_id].present? && params[:staff_id].present?
      @semester = Semester.find(params[:semester_id])
      @staff_member = Staff.find(params[:staff_id])

      section_ids = Teaching.where(staff: @staff_member)
                            .joins(section: :course_offering)
                            .where(course_offerings: { semester: @semester })
                            .pluck(:section_id)

      time_slots = TimeSlot.where(section_id: section_ids)
                           .includes(section: { course_offering: :course }, room: nil)

      @entries = time_slots.map do |ts|
        {
          day_of_week: ts.day_of_week,
          start_time: ts.start_time.strftime("%H:%M"),
          end_time: ts.end_time.strftime("%H:%M"),
          label: ts.section.course_offering.course.course_no,
          sublabel: "Sec #{ts.section.section_number}",
          detail: ts.room&.display_name || "TBA",
          color_key: ts.section.course_offering.course.course_no,
          url: course_offering_path(ts.section.course_offering)
        }
      end

      @total_load = Teaching.where(staff: @staff_member)
                            .joins(section: :course_offering)
                            .where(course_offerings: { semester: @semester })
                            .sum(:load_ratio)
    end
  end

  def curriculum
    @semesters = Semester.ordered
    @courses = Course.order(:course_no)

    if params[:semester_id].present? && params[:course_ids].present?
      @semester = Semester.find(params[:semester_id])
      @selected_course_ids = Array(params[:course_ids]).map(&:to_i)

      time_slots = TimeSlot.joins(section: { course_offering: :course })
                           .where(course_offerings: { semester: @semester, course_id: @selected_course_ids })
                           .includes(section: { course_offering: :course }, room: nil)

      @entries = time_slots.map do |ts|
        {
          day_of_week: ts.day_of_week,
          start_time: ts.start_time.strftime("%H:%M"),
          end_time: ts.end_time.strftime("%H:%M"),
          label: ts.section.course_offering.course.course_no,
          sublabel: "Sec #{ts.section.section_number}",
          detail: ts.room&.display_name || "TBA",
          color_key: ts.section.course_offering.course.course_no,
          url: course_offering_path(ts.section.course_offering)
        }
      end
    end
  end

  def student
    @semesters = Semester.ordered
    @students = Student.order(:student_id)

    if params[:semester_id].present? && params[:student_id].present?
      @semester = Semester.find(params[:semester_id])
      @student = Student.find(params[:student_id])

      grades = Grade.where(student: @student, year: @semester.year_be, semester: @semester.semester_number)
                    .includes(:course)

      @schedule_entries = []
      @entries = []

      grades.each do |grade|
        offering = CourseOffering.find_by(course: grade.course, semester: @semester)

        section = if grade.section_id
                    grade.section
                  elsif offering
                    offering.sections.order(:section_number).first
                  end

        @schedule_entries << { grade: grade, offering: offering, section: section }

        next unless section

        badge_html = if grade.grade.present?
                       "<span class='badge #{grade.grade_badge_class}' style='font-size:0.6rem'>#{grade.grade}</span>"
                     end

        section.time_slots.includes(:room).each do |ts|
          @entries << {
            day_of_week: ts.day_of_week,
            start_time: ts.start_time.strftime("%H:%M"),
            end_time: ts.end_time.strftime("%H:%M"),
            label: grade.course.course_no,
            sublabel: "Sec #{section.section_number}",
            detail: ts.room&.display_name || "TBA",
            color_key: grade.course.course_no,
            url: offering ? course_offering_path(offering) : nil,
            badge: badge_html
          }
        end
      end
    end
  end
end
