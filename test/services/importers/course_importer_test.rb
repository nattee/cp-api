require "test_helper"

class Importers::CourseImporterTest < ActiveSupport::TestCase
  test "transform_attributes stashes import_program for a new course" do
    importer = build_course_importer
    attrs = { course_no: "7777777", revision_year_be: 2565, name: "New One",
              program_name: programs(:cp_bachelor).program_code }
    result = importer.send(:transform_attributes, attrs)
    assert_equal programs(:cp_bachelor), result[:import_program]
  end

  test "transform_attributes links a new program to an existing course" do
    importer = build_course_importer
    course = courses(:intro_computing) # already linked to cp_bachelor via fixtures
    attrs = { course_no: course.course_no, revision_year_be: course.revision_year_be,
              name: course.name, program_name: programs(:cp_master).program_code }
    assert_difference "ProgramCourse.count", 1 do
      importer.send(:transform_attributes, attrs)
    end
    assert_includes course.reload.programs, programs(:cp_master)
  end

  test "transform_attributes does not link an unmatched program" do
    importer = build_course_importer
    attrs = { course_no: "7777778", revision_year_be: 2565, name: "Orphan",
              program_name: "Nonexistent Program" }
    assert_no_difference "ProgramCourse.count" do
      result = importer.send(:transform_attributes, attrs)
      assert_nil result[:import_program]
    end
  end

  private

  def build_course_importer
    di = DataImport.new(target_type: "Course", mode: "upsert", state: "pending", user: users(:admin))
    Importers::CourseImporter.new(di)
  end
end
