# test/services/book30/classifier_test.rb
require "test_helper"

class Book30ClassifierTest < ActiveSupport::TestCase
  L = Book30::Directory::Line
  P = Book30::Classifier::PoolStudent

  def line(cohort, no, first, last, prefix: cohort[0, 2], group: (prefix == "CT" ? "CS" : prefix), year: nil, alias_name: nil)
    year ||= Book30::Directory::EPOCHS[prefix] + cohort[2..].to_i - 1
    L.new(cohort: cohort, prefix: prefix, group: group, year: year, line_no: no, raw: "นาย #{first} #{last}",
          first: first, last: last, alias_name: alias_name, sex: "M")
  end

  def pool(id, first, last, group:, year:, track: nil)
    P.new(id: id, student_id: id.to_s, first: first, last: last, group: group, year: year, study_track: track)
  end

  def classify(lines, pools)
    Book30::Classifier.new(lines: lines, pools: pools).run
  end

  test "exact and tone-insensitive matches link; a track conflict is noted" do
    pools = { [ "CS", 2533 ] => [ pool(1, "สมชาย", "ใจดี", group: "CS", year: 2533, track: "regular"),
                               pool(2, "มานะ", "อดทน", group: "CS", year: 2533) ] }
    d = classify([ line("CT01", 1, "สมชาย", "ใจดี"), line("CT01", 2, "มานะ", "อดทน").tap { |l| l.last = "อดทน์" } ], pools)
    assert_equal %w[linked_exact linked_exact], d.map(&:outcome)
    assert_equal 1, d[0].student.id
    assert_includes d[0].note, "book says CT but study_track=regular"
    assert_equal 2, d[1].student.id
  end

  test "surname or first-name variants link and note which part differs" do
    pools = { [ "CP", 2530 ] => [ pool(1, "ปิยะรัตน์", "เงาจินตรักษ์", group: "CP", year: 2530),
                               pool(2, "วิษณุ", "สมบุญปีติ", group: "CP", year: 2530) ] }
    d = classify([ line("CP14", 1, "ปิยะรัตน์", "เสริมชัยวงศ์"), line("CP14", 2, "วิษณู", "สมบุญปีติ") ], pools)
    assert_equal %w[linked_variant linked_variant], d.map(&:outcome)
    assert_includes d[0].note, "book differs in surname"
    assert_includes d[1].note, "book differs in firstname"
  end

  test "same name in a neighbouring year links; thirteen years away is a namesake" do
    pools = { [ "CS", 2541 ] => [ pool(1, "จุณณ์", "ศรีสุธาพรรณ", group: "CS", year: 2541) ],
              [ "CS", 2535 ] => [ pool(2, "กฤษดา", "เรืองอารีย์รัชต์", group: "CS", year: 2535) ],
              [ "CS", 2540 ] => [ pool(9, "อื่น", "คนอื่น", group: "CS", year: 2540) ],
              [ "CS", 2548 ] => [ pool(8, "อื่น", "อีกคน", group: "CS", year: 2548) ] }
    d = classify([ line("CS27", 1, "จุณณ์", "ศรีสุธาพรรณ"), line("CS35", 1, "กฤษดา", "เรืองอารีย์รัชต์") ], pools)
    assert_equal "linked_other_year", d[0].outcome
    assert_includes d[0].note, "book year 2540, DB year 2541"
    assert_equal "create_namesake", d[1].outcome
    assert_nil d[1].student
    assert_includes d[1].note, "13 years away"
  end

  test "two book names on one DB student: closer wins, other becomes create_lost_claim" do
    pools = { [ "CP", 2535 ] => [ pool(1, "วรวิทย์", "สรณารักษ์โสภณ", group: "CP", year: 2535) ] }
    d = classify([ line("CP19", 1, "วรวิทย์", "สรณารักษ์โสภณ"), line("CP19", 2, "วรวิทย์", "ปรีชาวีรกุล") ], pools)
    assert_equal %w[linked_exact create_lost_claim], d.map(&:outcome)
    assert_includes d[1].note, "taken by a closer book name"
  end

  test "second listing of a linked person is ignored and points at the same student" do
    pools = { [ "CP", 2533 ] => [ pool(1, "เอกรินทร์", "กูลมนุญ", group: "CP", year: 2533) ], [ "CP", 2534 ] => [] }
    d = classify([ line("CP17", 1, "เอกรินทร์", "กูลมนุญ"), line("CP18", 1, "เอกรินทร์", "กูลมนุญ") ], pools)
    assert_equal %w[linked_exact second_listing], d.map(&:outcome)
    assert_equal 1, d[1].student.id
    assert_includes d[1].note, "same person linked under CP17"
  end

  test "book-only cohort creates; a repeat listing points at the head line" do
    d = classify([ line("CS06", 1, "อุไรลักษณ์", "พนัสบดี"), line("CS19", 3, "อุไรลักษณ์", "พนัสบดี") ], { [ "CS", 2532 ] => [ pool(5, "x", "y", group: "CS", year: 2532) ] })
    assert_equal %w[create_book_only_cohort second_listing], d.map(&:outcome)
    assert_same d[0], d[1].head
    assert_includes d[1].note, "placeholder created under CS06"
  end

  test "missing in a covered cohort, duplicate lines, unparsed lines, cross-programme note" do
    pools = { [ "CP", 2530 ] => [ pool(1, "ก", "ข", group: "CP", year: 2530) ], [ "CM", 2535 ] => [] }
    lines = [ line("CP14", 1, "สมชาย", "ใจดี"), line("CP14", 2, "สมชาย", "ใจดี"), line("CP14", 3, "เอนก", ""),
             line("CM01", 1, "สมชาย", "ใจดี") ]
    d = classify(lines, pools)
    assert_equal %w[create_missing duplicate_line unparsed create_book_only_cohort], d.map(&:outcome)
    assert_includes d[0].note, "also listed under CM01 (other programme)"
  end

  test "edit distance" do
    assert_equal 0, Book30::Classifier.edit_distance("กขค", "กขค")
    assert_equal 1, Book30::Classifier.edit_distance("กขค", "กค")
    assert_equal 2, Book30::Classifier.edit_distance("abc", "axd")
  end
end
