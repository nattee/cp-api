module Chulabooster
  module Convert
    module_function

    # CE→BE per the importer convention (+543 when the value looks like CE).
    def ce_to_be(value)
      return nil if value.nil? || value.to_s.strip.empty?
      n = value.to_i
      n < 2400 ? n + 543 : n
    end

    def bool(value)
      case value
      when true, 1, 1.0, "1", "true", "yes" then true
      else false
      end
    end

    # Normalize a scalar for comparison: trimmed, downcased string; nil/"" both -> "".
    def norm(value)
      value.to_s.strip.downcase
    end

    def int_or_nil(value)
      return nil if value.nil? || value.to_s.strip.empty?
      value.to_i
    end

    # CB course_id is "<4-digit CE year><course_no>", e.g. "20142110254" -> ["2110254", 2557].
    def parse_course_id(course_id)
      s = course_id.to_s
      [s[4..].to_s, ce_to_be(s[0, 4])]
    end
  end
end
