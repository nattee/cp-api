require "test_helper"

class Importers::GradeImporterTest < ActiveSupport::TestCase
  # resolve_course's placeholder branch raised UnknownAttributeError after the Course<->Program
  # M:N remodel removed Course#program=. Placeholders are now created program-less.
  test "resolve_course creates a program-less placeholder for a totally unknown course" do
    importer = Importers::GradeImporter.new(DataImport.new)
    course = nil
    assert_difference "Course.count", 1 do
      course = importer.send(:resolve_course, "20239999999")
    end
    assert_equal "9999999", course.course_no
    assert_equal 2566, course.revision_year_be  # 2023 CE -> BE
    assert_equal "placeholder", course.auto_generated
    assert_empty course.programs
  end

  test "resolve_course_by_no creates a program-less placeholder for an unknown course_no" do
    importer = Importers::GradeImporter.new(DataImport.new)
    course = nil
    assert_difference "Course.count", 1 do
      course = importer.send(:resolve_course_by_no, "8888888", -1)
    end
    assert_equal "8888888", course.course_no
    assert_equal(-1, course.revision_year_be)
    assert_equal "placeholder", course.auto_generated
    assert_empty course.programs
  end
end
