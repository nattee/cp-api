# Restores Thai combining marks the model dropped while copying Thai out of
# tool results into its reply.
#
# WHY: qwen3.5 (the LINE bot's model, thinking mode on) stochastically drops
# combining marks — tone marks, upper/lower vowels, thanthakhat — in long Thai
# replies: prod 2026-09-12 listed 25 lecturer names and misspelled 24 of them
# ("สุธี เรืองวิเศษ" → "สธ เรืองวเศษ", "อาจารย์" → "อาจารย"). The marks are present
# in what we SEND (tool results) and already missing in the raw HTTP response,
# so this is model-side; repetition penalty, top_p/top_k and temperature were
# all tested and do not fix it (disabling thinking helps — see
# LlmService#finalize_reply — but does not eliminate it). Like
# MarkdownScrubber, this is a deterministic post-processor for model residue.
#
# HOW: the conversation's own sources — tool results, the user's messages, and
# a small fixed vocabulary — are the ground truth the model copied from. Each
# Thai run in the reply is replaced by the source word it was garbled from when
# ALL of these hold:
#   1. the run is not itself a source word    (a correctly spelled word is never touched)
#   2. its mark-stripped form matches exactly ONE source word   (ambiguous → leave alone)
#   3. the marks differ in a way we trust to be damage:
#      - the source has MORE marks than the run — a drop, the common case — always;
#      - same count or more (a substituted or inserted mark, สิทธีอมร→สิทธิอมร) only for
#        words that came from the conversation's data, not the generic vocabulary,
#        and only when the consonant skeleton is long enough that a real minimal
#        pair (ไม้/ไม่, ป่า/ป้า) is implausible.
# Whole Thai runs are matched, so words the model glued together
# ("อาจารยประจำ") are not repaired — segmentation is out of scope — and a
# consonant the model swapped or added (บุณย→บุญย, นิภานันท์→นิภานันทน์) cannot
# be recovered either.
class Line::ThaiMarkRepair
  # ั ิ ี ึ ื ุ ู ฺ ็ ่ ้ ๊ ๋ ์ ํ ๎ — the Thai combining characters (Unicode Mn).
  MARKS = /[ัิ-ฺ็-๎]/
  THAI_RUN = /[฀-๿]+/

  # Bot vocabulary with no tool-result source, seen mark-dropped in prod
  # replies. Keep it short and multi-syllable: every entry is a candidate
  # replacement target, and rule 2 only protects against words that ARE listed.
  VOCABULARY = %w[
    อาจารย์ เจ้าหน้าที่ ข้อมูล ตัวอย่าง ทั้งหมด รายชื่อ ภาควิชา นิสิต หลักสูตร
    หน่วยกิต สถานะ ต้องการ ครบถ้วน บางส่วน หมายเหตุ ชั่วคราว พิเศษ เกษียณ
    บริหาร ผลการศึกษา ฐานข้อมูล ตารางสอน ไม่พบ
  ].freeze

  # Ground truth from an OpenAI-format message array: tool results and user
  # messages. The system prompt has no Thai and the model's own earlier turns
  # may themselves be damaged, so neither counts as a source. Accepts string
  # or symbol keys (ToolExecutor builds tool messages with symbols).
  def self.from_messages(messages)
    texts = messages.filter_map do |m|
      role = (m["role"] || m[:role]).to_s
      next unless %w[tool user].include?(role)
      (m["content"] || m[:content]).to_s
    end
    new(texts)
  end

  # Shortest mark-stripped skeleton for which a SUBSTITUTED or INSERTED mark is
  # repaired (dropped marks are repaired at any length). Two-letter skeletons
  # have real minimal pairs; a longer skeleton shared with a name the model was
  # copying is damage, not coincidence.
  MIN_SKELETON_FOR_SUBSTITUTION = 3

  def initialize(sources)
    @known = Set.new
    @by_key = {}
    @data_words = Set.new  # words seen in the conversation itself (tool results, user turns)
    Array(sources).each { |text| index(text) { |word| @data_words << word } }
    VOCABULARY.each { |word| index(word) }
  end

  def repair(text)
    return text if text.blank?
    text.gsub(THAI_RUN) { |run| replacement_for(run) || run }
  end

  # True when #repair would change the text — i.e. at least one Thai run is a
  # recognisable mark-dropped copy of a source word.
  def damaged?(text)
    return false if text.blank?
    text.scan(THAI_RUN).any? { |run| replacement_for(run) }
  end

  private

  def index(text)
    text.to_s.scan(THAI_RUN).each do |word|
      @known << word
      (@by_key[strip_marks(word)] ||= Set.new) << word
      yield word if block_given?
    end
  end

  def replacement_for(run)
    return nil if @known.include?(run)                          # rule 1
    key = strip_marks(run)
    candidates = @by_key[key]
    return nil unless candidates && candidates.size == 1        # rule 2
    original = candidates.first
    return original if original.scan(MARKS).size > run.scan(MARKS).size  # rule 3: dropped marks
    # Substituted / inserted mark: data words with a long enough skeleton only.
    @data_words.include?(original) && key.size >= MIN_SKELETON_FOR_SUBSTITUTION ? original : nil
  end

  def strip_marks(text)
    text.gsub(MARKS, "")
  end
end
