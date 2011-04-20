module URLHelpers
  include TemplateDataHelpers
  def url *segments
    path = make_path *segments
    if config[:wiki_prefix]
      path = config[:wiki_prefix] + path
    else
      path
    end
  end
  def path_for obj, type = nil
    make_path(*get_qs_segments(obj, type))
  end
  def url_for obj, type = nil
    url(*get_qs_segments(obj, type))
  end
  def make_path *segments
    segments.map { |e| MediaWiki::wiki_to_uri(e.to_s.gsub("*", "_STAR_").gsub(/[^a-z0-9_.-]/i, "_")) }.join "/"
  end
  def get_qs_segments obj, type
    values = []
    unless obj.is_a?(QS::Plugin) || obj.is_a?(Bundle)
      values += get_qs_segments(obj.plugin, nil)
    end
    values << obj.class.name.gsub("QS::", "")
    if type.nil? && (obj.is_a?(QS::Plugin) || obj.is_a?(Bundle))
      values << obj.name
    else
      values << obj.id
    end
    values << type if type
    values
  end
end