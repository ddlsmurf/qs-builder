module Helpers
  # yields value if its to_s has length
  def when_not_empty value, &block
    yield(value) if (value || '').to_s.length > 0
  end
  # wrap the text in prefix and suffix if its not empty.
  # if a block is given, its return value is used as the text if non false
  def wrap text = nil, prefix = "<nowiki>", suffix = "</nowiki>"
    result = ""
    text = (yield(text)) || text if block_given?
    when_not_empty(text) { result = "#{prefix}#{text}#{suffix}" }
    result
  end
  # wrapes in <code> tags
  def code text
    wrap_tag(text, "code")
  end
  # wraps in html like tags. does not escape text.
  def wrap_tag text, tag = "nowiki", &block
    wrap(text, "<#{tag}>", "</#{tag}>", &block)
  end
  # if enumerable is nil, return nil
  # if enumerable has any items, concatenate them, separating them
  # using sep and last_sep
  # 
  # [sep] separator to use between all items except the last and before-last
  # [last_sep] is the separator to use between the before-last and last items
  def enum_with_sep enumerable, last_sep = ' and ', sep = ', '
    return nil unless enumerable
    result = []
    have_item = false
    prev_item = nil
    enumerable.each do |*arguments|
      if !have_item
        have_item = true
      else
        result << sep if !result.empty?
        result << prev_item
      end
      prev_item = block_given? ? yield(*arguments) : arguments.first
    end
    if have_item
      result << last_sep if !result.empty?
      result << prev_item
    end
    result.join("")
  end
end