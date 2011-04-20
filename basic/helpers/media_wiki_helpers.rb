# Helpers for writing media wiki formatted documents
module MediaWikiHelpers
  # wraps in <nowiki> tags
  def nowiki text, &block
    wrap_tag(text, "nowiki", &block)
  end
  # Creates a [[File: path]] link
  def image path
    wrap(path, "[[File:", "]]")
  end
  # Creates a link to the provided internal url, with an optional title
  def internal_link url, title = nil
    wrap("#{url}#{title ? "|#{title}" : ""}", "[[", "]]")
  end
  def template_argument name, default = nil
    "{{{#{name + (default.to_s.length > 0 ? "|" + default.to_s : "")}}}}"
  end
  def template_call name, *args
    args += args.pop.map { |k, v| "#{k} = #{v}" if v && v.to_s.length > 0 } if args.last.is_a?(Hash)
    args = args.map { |e| e.to_s }
    args.pop while args.last == ""
    args = args.join("\n| ")
    "{{#{name}#{args.length == 0 ? "" : "| #{args}"}}}"
  end
  # Include specified URL from the global namespace
  # http://www.mediawiki.org/wiki/Templates
  def include_template url, *args
    template_call ":#{url}", *args
  end
  # Builds a parser function call
  # 
  # Reference: http://www.mediawiki.org/wiki/Help:Extension:ParserFunctions
  def func_call name, *args
    first_arg = args.shift.to_s
    template_call "##{name}#{first_arg.length == 0 ? "" : ": #{first_arg}"}", *args
  end
  def if_exists url, if_true, if_false = nil
    func_call "ifexist", url, if_true, if_false
  end
  # Includes the template #{url}_Manual if it exists, falling
  # back to url, or content_if_neither_exists
  def overiddable_template url, content_if_neither_exists = nil
    override_name = "#{url}_Manual"
    if_exists override_name, include_template(override_name), if_exists(url, include_template(url), content_if_neither_exists)
  end
  # Builds an internal link to the provided QS::QSObject
  def qs_object_link obj, type = nil
    internal_link url_for(obj, type), obj.name
  end
  # Builds an internal link to the specified QS::ObjectType
  # [type] QS::ObjectType to link to
  # [file_types] Optional. An array of file types displayed if QS::ObjectType#files? of type is true
  def qs_object_type_link type, file_types = nil
    name = type.name
    internal_link(url_for(type, nil), name) + (file_types && type.files? ?
      hover(" (types)", wrap(enum_with_sep(file_types, ' or '), ' (', ')')) || "" : "")
  end
  # Replaces html <a href="http:.."> formatted links in str into
  # wiki media [http:...] links
  def html_links_to_wikimedia str
    return str unless str.is_a?(String)
    str.gsub(/<\s*a\b([^>]+)>/i) do |match|
      attrs = {}
      $1.scan(/([^ =]+)=(?:'([^']+)'|"([^"]+)"|([^ >]+))/i) do |matches|
        attrs[$1] = matches.drop(2).select {|e| e}.first
      end
      raise "Failed to understand html #{str.inspect}" unless attrs['href']
      "[#{attrs['href']} "
    end.gsub(/<\/a>/i, "]")
  end
  def external_link url, title = nil
    wrap("#{url}#{title ? " #{title}" : ""}", "[", "]")
  end
  # Generates a span with specified title
  def hover label, text
    wrap(text, "<span title=\"", "\" style=\"border-bottom:1px dotted\">#{label}</span>")
    #wrap(text, "{{H:title|#{label}|", "}}")
  end
  def youtube id
    wrap(id, "{{#ev:youtube|", "}}")
  end
  def redirect target_link
    "#REDIRECT #{target_link}"
  end
  def list(enum, depth = 1)
    prefix = "\n#{"*" * depth} "
    wrap(enum ? enum.join(prefix) : nil, prefix, "")
  end
end
