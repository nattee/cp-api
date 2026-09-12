require "test_helper"

class Line::ThaiMarkRepairTest < ActiveSupport::TestCase
  # Real prod damage (2026-09-12): the model copied lecturer names out of a
  # tool result and dropped combining marks — "สุธี เรืองวิเศษ" → "สธ เรืองวเศษ".
  TOOL_RESULT = '{"staff":[{"name_th":"อ.ดร.สุธี เรืองวิเศษ","initials":"SRS"},{"name_th":"รศ.ดร.นัทที นิภานันท์"}]}'.freeze

  test "restores a word whose marks were dropped, from a tool-result source" do
    repairer = Line::ThaiMarkRepair.new([ TOOL_RESULT ])
    assert_equal "• อ.ดร.สุธี เรืองวิเศษ (SRS)", repairer.repair("• อ.ดร.สธ เรืองวเศษ (SRS)")
  end

  test "repairs several words and leaves Latin text, digits and punctuation alone" do
    repairer = Line::ThaiMarkRepair.new([ TOOL_RESULT ])
    assert_equal "1. นัทที นิภานันท์ (NNN) — total 2", repairer.repair("1. นทที นภานนท (NNN) — total 2")
  end

  test "never touches a word that itself appears in the sources" do
    repairer = Line::ThaiMarkRepair.new([ "สุธี", "สธ" ])
    # "สธ" is a legitimate source word here, so it must stay even though "สุธี" shares its key.
    assert_equal "สธ", repairer.repair("สธ")
  end

  test "leaves an ambiguous key alone" do
    repairer = Line::ThaiMarkRepair.new([ "สุธี", "สีธี" ])  # both strip to "สธ"
    assert_equal "สธ", repairer.repair("สธ")
  end

  test "repairs a substituted or inserted mark in a long data word" do
    repairer = Line::ThaiMarkRepair.new([ '{"name_th":"ผศ.ดร.พิชญะ สิทธีอมร"},{"name_th":"เนื่องวงศ์ ทวยเจริญ"}' ])
    assert_equal "พิชญะ สิทธีอมร", repairer.repair("พิชญะ สิทธิอมร")      # ี → ิ substituted
    assert_equal "เนื่องวงศ์ ทวยเจริญ", repairer.repair("เนื่องวงศ์ ทุวยเจริญ")  # ุ inserted
  end

  test "a substituted mark on a short skeleton is left alone — real minimal pairs exist" do
    repairer = Line::ThaiMarkRepair.new([ "สุธี" ])
    assert_equal "สูธี", repairer.repair("สูธี")  # skeleton "สธ" is only 2 letters
  end

  test "a substituted mark in generic vocabulary is left alone — only drops are repaired there" do
    repairer = Line::ThaiMarkRepair.new([])
    assert_equal "ตัวอย้าง", repairer.repair("ตัวอย้าง")   # ่ → ้: not a drop, vocabulary word
    assert_equal "ตัวอย่าง", repairer.repair("ตวอยาง")     # drops are still repaired
  end

  test "repairs common bot vocabulary that has no tool-result source" do
    repairer = Line::ThaiMarkRepair.new([])
    assert_equal "อาจารย์ ประจำ", repairer.repair("อาจารย ประจำ")
  end

  test "does not attempt words the model glued together" do
    repairer = Line::ThaiMarkRepair.new([])
    assert_equal "อาจารยประจำ", repairer.repair("อาจารยประจำ")
  end

  test "damaged? reports whether a repair would change the text" do
    repairer = Line::ThaiMarkRepair.new([ TOOL_RESULT ])
    assert repairer.damaged?("รายชื่อ: สธ เรืองวเศษ")
    assert_not repairer.damaged?("รายชื่อ: สุธี เรืองวิเศษ")
    assert_not repairer.damaged?("")
  end

  test "from_messages uses tool results and user messages, not the prompt or the model's own turns" do
    messages = [
      { "role" => "system", "content" => "ระบบ" },
      { "role" => "user", "content" => "อาจารย์ วิษณุ สอนอะไร" },
      { "role" => "assistant", "content" => "ตอบผิด" },
      { role: :tool, content: TOOL_RESULT, tool_call_id: "c1" }  # symbol keys, as ToolExecutor builds them
    ]
    repairer = Line::ThaiMarkRepair.from_messages(messages)
    assert_equal "วิษณุ กับ สุธี", repairer.repair("วษณุ กับ สธ")
    assert_equal "ระบบ ตอบผด", repairer.repair("ระบบ ตอบผด")  # "ตอบผิด" came from an assistant turn: not a source
  end

  test "blank input is returned unchanged" do
    repairer = Line::ThaiMarkRepair.new([ TOOL_RESULT ])
    assert_equal "", repairer.repair("")
    assert_nil repairer.repair(nil)
  end
end
