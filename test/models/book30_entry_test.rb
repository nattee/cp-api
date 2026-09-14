require "test_helper"

class Book30EntryTest < ActiveSupport::TestCase
  def entry(**attrs)
    Book30Entry.new({ cohort: "CP14", year_be: 2530, line_no: 1, raw_line: "นาย สมชาย ใจดี",
                      first_name_th: "สมชาย", last_name_th: "ใจดี", outcome: "linked_exact" }.merge(attrs))
  end

  test "valid entry" do
    assert entry.valid?
  end

  test "outcome must be known" do
    e = entry(outcome: "guess")
    assert_not e.valid?
    assert_includes e.errors[:outcome], "is not included in the list"
  end

  test "line_no unique within cohort" do
    entry(student: students(:active_student)).save!
    dup = entry
    assert_not dup.valid?
    assert_includes dup.errors[:line_no], "has already been taken"
  end

  test "outcome families cover every outcome once" do
    all = Book30Entry::LINK_OUTCOMES + Book30Entry::IGNORE_OUTCOMES + Book30Entry::CREATE_OUTCOMES
    assert_equal Book30Entry::OUTCOMES.sort, all.sort
    assert_equal all.size, all.uniq.size
    assert_equal "create", entry(outcome: "create_missing").family
  end
end
