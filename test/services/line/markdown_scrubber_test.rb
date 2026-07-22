require "test_helper"

class Line::MarkdownScrubberTest < ActiveSupport::TestCase
  test "strips bold pairs including Thai content" do
    assert_equal "นิสิต CP53 มี 0 คน", Line::MarkdownScrubber.scrub("นิสิต **CP53** มี **0 คน**")
  end

  test "strips underline emphasis pairs" do
    assert_equal "important", Line::MarkdownScrubber.scrub("__important__")
  end

  test "strips ATX headers at line start" do
    assert_equal "ผลการเรียน\nรายละเอียด", Line::MarkdownScrubber.scrub("## ผลการเรียน\n### รายละเอียด")
  end

  test "strips inline code backticks" do
    assert_equal "ใช้ student_lookup ค่ะ", Line::MarkdownScrubber.scrub("ใช้ `student_lookup` ค่ะ")
  end

  test "drops code fence lines but keeps content" do
    assert_equal "A: 12\nB: 8\n", Line::MarkdownScrubber.scrub("```\nA: 12\nB: 8\n```\n")
  end

  test "converts links to text (url)" do
    assert_equal "ดูที่นี่ (http://example.com)", Line::MarkdownScrubber.scrub("[ดูที่นี่](http://example.com)")
  end

  test "leaves single asterisks, bullets, and emoji alone" do
    text = "3*4 = 12\n• ข้อแรก\n📊 A: 5 • B: 3"
    assert_equal text, Line::MarkdownScrubber.scrub(text)
  end

  test "passes blank input through" do
    assert_equal "", Line::MarkdownScrubber.scrub("")
    assert_nil Line::MarkdownScrubber.scrub(nil)
  end
end
