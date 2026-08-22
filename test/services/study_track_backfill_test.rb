require "test_helper"

class StudyTrackBackfillTest < ActiveSupport::TestCase
  LABEL = StudyTrackBackfill::SPECIAL_LABEL

  def backfill
    StudyTrackBackfill.new(cb_rows: {}, commit: false)
  end

  def cs_student(year:, sid: nil, label: nil)
    Student.new(
      student_id: sid || "#{year - 2500}70000021",
      admission_year_be: year,
      program: programs(:cs_master_1995),
      enrollment_method: label,
      first_name: "a", last_name: "b", first_name_th: "ก", last_name_th: "ข"
    )
  end

  test "label marks special in any group" do
    decision = backfill.decide(cs_student(year: 2545, label: LABEL), nil)
    assert_equal "special", decision.track
    assert_equal "label:enrollment_method", decision.evidence

    cm = cs_student(year: 2560, label: LABEL)
    cm.program = programs(:cp_master)
    assert_equal "special", backfill.decide(cm, nil).track
  end

  test "cb project 212 with special fee is special (2533-2553)" do
    decision = backfill.decide(cs_student(year: 2545), { "project" => "212", "fee_type" => "07" })
    assert_equal "special", decision.track
  end

  test "cb project 201 with regular fee is regular (2533-2553)" do
    decision = backfill.decide(cs_student(year: 2545), { "project" => "201", "fee_type" => "01" })
    assert_equal "regular", decision.track
  end

  test "label vs classifier conflict goes to review" do
    decision = backfill.decide(cs_student(year: 2545, label: LABEL), { "project" => "201", "fee_type" => "01" })
    assert_nil decision.track
    assert decision.review_reason.present?
  end

  test "segment 71 is special in 2554-2560" do
    assert_equal "special", backfill.decide(cs_student(year: 2556, sid: "5671000021"), nil).track
  end

  test "segment 70 in 2554-2560 is regular only with plan-201 corroboration" do
    regular = backfill.decide(cs_student(year: 2556, sid: "5670000021"), { "project" => "201", "fee_type" => "07" })
    assert_equal "regular", regular.track

    uncorroborated = backfill.decide(cs_student(year: 2556, sid: "5670000021"), { "project" => "212", "fee_type" => "07" })
    assert_nil uncorroborated.track
    assert_match(/without plan-201 corroboration/, uncorroborated.review_reason)

    no_cb = backfill.decide(cs_student(year: 2556, sid: "5670000021"), nil)
    assert_nil no_cb.track
    assert no_cb.review_reason.present?
  end

  test "label beats a segment-70 plan-212 row in 2554-2560" do
    decision = backfill.decide(cs_student(year: 2556, sid: "5670000021", label: LABEL), { "project" => "212", "fee_type" => "07" })
    assert_equal "special", decision.track
  end

  test "pre-2533 CS is regular, 2561-plus CS is nil, non-CS unlabeled is nil" do
    assert_equal "regular", backfill.decide(cs_student(year: 2530), nil).track
    assert_nil backfill.decide(cs_student(year: 2563, sid: "6372000021"), nil).track

    cm = cs_student(year: 2545)
    cm.program = programs(:cp_master)
    decision = backfill.decide(cm, nil)
    assert_nil decision.track
    assert_nil decision.review_reason
  end

  test "CS 2533-2553 with no CB row goes to review" do
    decision = backfill.decide(cs_student(year: 2545), nil)
    assert_nil decision.track
    assert_match(/not in CB/, decision.review_reason)
  end

  test "CS 2533-2553 with unrecognized CB combo goes to review" do
    decision = backfill.decide(cs_student(year: 2545), { "project" => "212", "fee_type" => "01" })
    assert_nil decision.track
    assert_match(/unrecognized CB combo/, decision.review_reason)
  end
end
