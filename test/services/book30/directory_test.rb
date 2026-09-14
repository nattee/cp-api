require "test_helper"

class Book30DirectoryTest < ActiveSupport::TestCase
  def line_xml(x0, y0, text)
    chars = text.each_char.map { |c| %(<char quad="0 0 0 0" x="0" y="0" c="#{CGI.escapeHTML(c)}"/>) }.join
    %(<line bbox="#{x0} #{y0} 100 10" wmode="0" dir="1 0"><font name="F" size="9">#{chars}</font></line>)
  end

  def xml
    # left column (x < 180) reads before the right column; lines within a column sort by y
    %(<document><page id="page1" width="500" height="700">
      #{line_xml(50, 60, 'นางสาว สมหญิง ดีใจ')}
      #{line_xml(50, 20, 'รุ่น CP14')}
      #{line_xml(50, 40, 'นาย สมชาย ใจดี')}
      #{line_xml(50, 80, '(แซ่ลี้)')}
      #{line_xml(50, 100, 'CP CHULA    30th ANNIVERSARY')}
      #{line_xml(200, 30, 'รุ่น CT01')}
      #{line_xml(200, 50, 'ดร. กอบกุล (เตชะ) วณิช')}
      #{line_xml(200, 70, 'นาย เอนก')}
    </page></document>)
  end

  test "groups lines under cohort headers in reading order, dropping noise" do
    dir = Book30::Directory.new(xml)
    assert_equal({ "CP14" => [ "นาย สมชาย ใจดี", "นางสาว สมหญิง ดีใจ", "(แซ่ลี้)" ],
                   "CT01" => [ "ดร. กอบกุล (เตชะ) วณิช", "นาย เอนก" ] }, dir.cohorts)
  end

  test "lines carry cohort facts, parsed names, folded aliases and sex" do
    lines = Book30::Directory.new(xml).lines
    assert_equal %w[CP14 CP14 CT01 CT01], lines.map(&:cohort)
    a, b, c, d = lines
    assert_equal [ "CP", "CP", 2530, 1, "สมชาย", "ใจดี", nil, "M" ], [ a.prefix, a.group, a.year, a.line_no, a.first, a.last, a.alias_name, a.sex ]
    assert_equal [ 2, "สมหญิง", "ดีใจ", "แซ่ลี้", "F" ], [ b.line_no, b.first, b.last, b.alias_name, b.sex ]
    assert_equal [ "CT", "CS", 2533, 1, "กอบกุล", "วณิช", "เตชะ", nil ], [ c.prefix, c.group, c.year, c.line_no, c.first, c.last, c.alias_name, c.sex ]
    assert_equal [ "เอนก", "" ], [ d.first, d.last ]
  end

  test "decode maps PUA glyphs and reorders marks" do
    # U+F70A is the PSL private-use variant of the tone mark ่ ; the PDF puts it BEFORE the vowel ุ
    assert_equal "รุ่น", Book30::Directory.decode("ร\uF70A\u0E38น")
    assert_equal "รุ่น", Book30::Directory.decode("&#xe23;&#xf70a;&#xe38;&#xe19;")
  end

  test "normalize drops tone marks and spaces; loose_key; sex from titles" do
    assert_equal "ใจดี", Book30::Directory.normalize("ใจ ดี")
    assert_equal "สมชาย|ใจดี", Book30::Directory.loose_key("สมชาย", "ใจดี้")
    assert_equal "F", Book30::Directory.sex_from_title("นาง มาลี ดี")
    assert_equal "F", Book30::Directory.sex_from_title("ว่าที่ ร.ต.หญิง มาลี ดี")
    assert_equal "M", Book30::Directory.sex_from_title("ว่าที่ ร.ต. สมชาย ดี")
    assert_nil Book30::Directory.sex_from_title("ผศ. กอบกุล ดี")
  end
end
