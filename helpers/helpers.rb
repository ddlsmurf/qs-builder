module Helpers
  def when_not_empty value, &block
    yield(value) if (value || '').to_s.length > 0
  end
  def wrap text = nil, prefix = "<nowiki>", suffix = "</nowiki>"
    result = ""
    text = (yield(text)) || text if block_given?
    when_not_empty(text) { result = "#{prefix}#{text}#{suffix}" }
    result
  end
  def code text
    wrap_tag(text, "code")
  end
  def wrap_tag text, tag = "nowiki", &block
    wrap(text, "<#{tag}>", "</#{tag}>", &block)
  end
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