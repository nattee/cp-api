class SchedulesController < ApplicationController
  helper_method :load_cell_class

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

  def workload
    current_year = Time.current.year + 543
    @start_year = (params[:start_year].presence || current_year).to_i
    @end_year = (params[:end_year].presence || current_year).to_i
    @staff_type = params[:staff_type].presence
    @low_threshold = (params[:low_threshold].presence || 1).to_f
    @high_threshold = (params[:high_threshold].presence || 2).to_f

    year_range = @start_year..@end_year

    @semesters = Semester.where(year_be: year_range).ordered.to_a

    base = Teaching.joins(:staff, section: { course_offering: :semester })
                   .where(semesters: { year_be: year_range })
    base = base.where(staffs: { staff_type: @staff_type }) if @staff_type.present?

    raw = base.group(:staff_id, "semesters.year_be", "semesters.semester_number")
              .sum(:load_ratio)

    staff_ids = raw.keys.map(&:first).uniq
    @staffs = Staff.where(id: staff_ids).index_by(&:id)

    @workload_data = {}
    raw.each do |(staff_id, year_be, semester_number), load|
      @workload_data[staff_id] ||= {}
      @workload_data[staff_id][[year_be, semester_number]] = load
    end
  end

  def conflicts
    @semesters = Semester.ordered
    @conflict_type = params[:conflict_type].presence || "both"

    if params[:semester_id].present?
      @semester = Semester.find(params[:semester_id])
      @conflicts = []

      if @conflict_type.in?(%w[room both])
        @conflicts += find_room_conflicts(@semester)
      end

      if @conflict_type.in?(%w[staff both])
        @conflicts += find_staff_conflicts(@semester)
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

  private

  def load_cell_class(load, low, high)
    return nil unless load
    if load < low
      "table-success"
    elsif load > high
      "table-danger"
    end
  end

  def find_room_conflicts(semester)
    slots = TimeSlot.joins(section: :course_offering)
                    .where(course_offerings: { semester_id: semester.id })
                    .where.not(room_id: nil)
                    .includes(:room, section: { course_offering: :course })
                    .to_a

    conflicts = []
    slots.group_by { |ts| [ts.room_id, ts.day_of_week] }.each do |(_room_id, _day), group|
      group.combination(2).each do |a, b|
        if times_overlap?(a, b)
          conflicts << {
            type: "Room",
            day: TimeSlot::DAY_NAMES[a.day_of_week],
            time: "#{a.start_time.strftime('%H:%M')}-#{[a.end_time, b.end_time].max.strftime('%H:%M')}",
            conflict: a.room.display_name,
            details: "#{slot_label(a)} vs #{slot_label(b)}"
          }
        end
      end
    end
    conflicts
  end

  def find_staff_conflicts(semester)
    teachings = Teaching.joins(section: [:time_slots, :course_offering])
                       .where(course_offerings: { semester_id: semester.id })
                       .includes(:staff, section: [:time_slots, { course_offering: :course }])
                       .to_a

    conflicts = []
    teachings.group_by(&:staff_id).each do |_staff_id, staff_teachings|
      next if staff_teachings.size < 2

      pairs = staff_teachings.combination(2).to_a
      pairs.each do |t1, t2|
        next if t1.section_id == t2.section_id

        t1.section.time_slots.each do |ts1|
          t2.section.time_slots.each do |ts2|
            next unless ts1.day_of_week == ts2.day_of_week

            if times_overlap?(ts1, ts2)
              conflicts << {
                type: "Staff",
                day: TimeSlot::DAY_NAMES[ts1.day_of_week],
                time: "#{ts1.start_time.strftime('%H:%M')}-#{[ts1.end_time, ts2.end_time].max.strftime('%H:%M')}",
                conflict: t1.staff.display_name_th,
                details: "#{slot_label(ts1)} vs #{slot_label(ts2)}"
              }
            end
          end
        end
      end
    end
    conflicts.uniq { |c| [c[:type], c[:day], c[:conflict], c[:details]] }
  end

  def times_overlap?(a, b)
    a.start_time < b.end_time && b.start_time < a.end_time
  end

  def slot_label(ts)
    course = ts.section.course_offering.course
    "#{course.course_no} Sec #{ts.section.section_number}"
  end
end
