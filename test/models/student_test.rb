require "test_helper"

class StudentTest < ActiveSupport::TestCase
  # --- Validations ---

  test "valid student" do
    student = Student.new(student_id: "9999900001", first_name: "Test", last_name: "Student", admission_year: 2567, program: programs(:cp_bachelor))
    assert student.valid?
  end

  test "requires student_id" do
    student = students(:active_student).dup
    student.student_id = nil
    assert_not student.valid?
    assert_includes student.errors[:student_id], "can't be blank"
  end

  test "student_id must be unique" do
    student = Student.new(student_id: students(:active_student).student_id, first_name: "Dup", last_name: "Student", admission_year: 2567)
    assert_not student.valid?
    assert_includes student.errors[:student_id], "has already been taken"
  end

  test "requires first_name" do
    student = students(:active_student).dup
    student.student_id = "9999900002"
    student.first_name = nil
    assert_not student.valid?
    assert_includes student.errors[:first_name], "can't be blank"
  end

  test "requires last_name" do
    student = students(:active_student).dup
    student.student_id = "9999900003"
    student.last_name = nil
    assert_not student.valid?
    assert_includes student.errors[:last_name], "can't be blank"
  end

  test "requires admission_year" do
    student = students(:active_student).dup
    student.student_id = "9999900004"
    student.admission_year = nil
    assert_not student.valid?
    assert_includes student.errors[:admission_year], "can't be blank"
  end

  test "admission_year must be integer" do
    student = students(:active_student).dup
    student.student_id = "9999900005"
    student.admission_year = 25.5
    assert_not student.valid?
    assert_includes student.errors[:admission_year], "must be an integer"
  end

  test "status must be valid" do
    student = students(:active_student).dup
    student.student_id = "9999900006"
    student.status = "expelled"
    assert_not student.valid?
    assert_includes student.errors[:status], "is not included in the list"
  end

  test "status defaults to active" do
    student = Student.new
    assert_equal "active", student.status
  end

  # --- Scopes ---

  test "active scope returns only active students" do
    results = Student.active
    assert results.all? { |s| s.status == "active" }
    assert_includes results, students(:active_student)
    assert_not_includes results, students(:graduated_student)
    assert_not_includes results, students(:on_leave_student)
  end

  # --- Helper methods ---

  test "full_name returns first and last name" do
    student = students(:active_student)
    assert_equal "Thanawat Sricharoen", student.full_name
  end

  test "full_name_th returns Thai first and last name" do
    student = students(:active_student)
    assert_equal "ธนวัฒน์ ศรีเจริญ", student.full_name_th
  end

  test "full_name_th returns nil when both Thai names are blank" do
    student = students(:on_leave_student)
    assert_nil student.full_name_th
  end

  # --- Status methods ---

  test "active? returns true for active student" do
    assert students(:active_student).active?
    assert_not students(:graduated_student).active?
  end

  test "graduated? returns true for graduated student" do
    assert students(:graduated_student).graduated?
    assert_not students(:active_student).graduated?
  end

  test "on_leave? returns true for on_leave student" do
    assert students(:on_leave_student).on_leave?
    assert_not students(:active_student).on_leave?
  end
end
