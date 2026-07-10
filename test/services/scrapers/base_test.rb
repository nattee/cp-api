require "test_helper"

# Covers the teacher-initials namespace rules in Scrapers::Base#import_course_data.
# Teacher codes are only unique within the course-owning faculty, so initials are
# resolved against Staff only for faculty-21 courses (or allowlisted pairs);
# would-be matches elsewhere are reported, never imported.
class Scrapers::BaseTest < ActiveSupport::TestCase
  setup do
    # Concrete backend instance; the behavior under test lives in Scrapers::Base.
    # sem_2568_2 avoids fixture overlap with existing sem_2568_1 offerings.
    @scraper = Scrapers::CuGetReg.new(semester: semesters(:sem_2568_2), study_program: "S")

    # Owned by CULI (faculty 55) — teacher initials on its sections live in CULI's
    # namespace, not ours. Created here rather than in fixtures because several
    # tests elsewhere assert on the global course count / revision-year sets.
    Course.create!(
      name: "EXPERIENTIAL ENGLISH I", course_no: "5500111", revision_year_be: 2560,
      is_gened: true, credits: 3, l_credits: 3, nl_credits: 0,
      l_hours: 3, nl_hours: 0, s_hours: 6, is_thesis: false
    )
  end

  test "resolves initials and creates teaching on faculty-21 course" do
    summary = nil
    assert_difference -> { Teaching.count }, 1 do
      summary = @scraper.import_course_data(course_data("2110101", teachers: ["JS"]))
    end

    assert_equal 1, summary[:teachings]
    assert_empty summary[:cross_faculty_matches]
    offering = CourseOffering.find_by(course: courses(:intro_computing), semester: semesters(:sem_2568_2))
    assert_equal [staffs(:lecturer_smith)], offering.sections.first.teachings.map(&:staff)
  end

  test "reports unknown initials on faculty-21 course as unresolved" do
    summary = @scraper.import_course_data(course_data("2110101", teachers: ["XYZ"]))

    assert_equal ["XYZ"], summary[:unresolved_teachers]
    assert_empty summary[:cross_faculty_matches]
  end

  test "does not create teaching on foreign-faculty course and reports the would-be match" do
    summary = nil
    assert_no_difference -> { Teaching.count } do
      summary = @scraper.import_course_data(course_data("5500111", teachers: ["JS"]))
    end

    assert_equal 0, summary[:teachings]
    assert_equal [{ course_no: "5500111", initials: "JS" }], summary[:cross_faculty_matches]
    assert_empty summary[:unresolved_teachers]
  end

  test "ignores initials on foreign-faculty course that match no staff" do
    summary = @scraper.import_course_data(course_data("5500111", teachers: ["XYZ"]))

    assert_empty summary[:unresolved_teachers]
    assert_empty summary[:cross_faculty_matches]
  end

  test "allowlisted pair creates teaching on foreign-faculty course, others still reported" do
    with_allowlist("5500111" => %w[JS]) do
      summary = nil
      assert_difference -> { Teaching.count }, 1 do
        summary = @scraper.import_course_data(course_data("5500111", teachers: %w[JS JJ]))
      end

      assert_equal 1, summary[:teachings]
      assert_equal [staffs(:lecturer_smith)], Teaching.last.section.teachings.map(&:staff)
      assert_equal [{ course_no: "5500111", initials: "JJ" }], summary[:cross_faculty_matches]
    end
  end

  test "reported cross-faculty matches are deduplicated across sections" do
    data = course_data("5500111", teachers: ["JS"])
    data[:sections] << {
      section_no: "2", note: nil, enrollment_current: 5, enrollment_max: 30,
      classes: [{ type: "LECT", day: "TU", start_time: "13:00", end_time: "16:00",
                  building: "MHVH", room: "1502", teachers: ["JS"] }]
    }

    summary = @scraper.import_course_data(data)

    assert_equal [{ course_no: "5500111", initials: "JS" }], summary[:cross_faculty_matches]
  end

  private

  def course_data(course_no, teachers:)
    {
      course_no: course_no,
      sections: [
        {
          section_no: "1", note: nil, enrollment_current: 10, enrollment_max: 30,
          classes: [
            { type: "LECT", day: "MO", start_time: "09:00", end_time: "12:00",
              building: "ENG4", room: "303", teachers: teachers }
          ]
        }
      ]
    }
  end

  def with_allowlist(mapping)
    original = Scrapers::Base::CROSS_FACULTY_TEACHING_ALLOWLIST
    Scrapers::Base.send(:remove_const, :CROSS_FACULTY_TEACHING_ALLOWLIST)
    Scrapers::Base.const_set(:CROSS_FACULTY_TEACHING_ALLOWLIST, mapping.freeze)
    yield
  ensure
    Scrapers::Base.send(:remove_const, :CROSS_FACULTY_TEACHING_ALLOWLIST)
    Scrapers::Base.const_set(:CROSS_FACULTY_TEACHING_ALLOWLIST, original)
  end
end
