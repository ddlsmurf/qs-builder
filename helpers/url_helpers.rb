module URLHelpers
  include TemplateDataHelpers
  def path *segments
    File.join(*segments)
  end
  def url *segments
    path = path(*segments)
    if config[:wiki_prefix]
      path = config[:wiki_prefix] + path
    else
      path
    end
  end
  def path_for obj, type = nil
    path(*get_qs_segments(obj, type))
  end
  def url_for obj, type = nil
    url(*get_qs_segments(obj, type))
  end
  def get_qs_segments obj, type = nil
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