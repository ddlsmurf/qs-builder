# Helper methods to build paths and URLs to QS objects
module URLHelpers
  include TemplateDataHelpers
  # Make a FS-safe path string from the provided segments
  def path *segments
    File.join(*segments)
  end
  # Build the url from the provided path segments
  def url *segments
    path = path(*segments)
    if config[:wiki_prefix]
      path = config[:wiki_prefix] + path
    else
      path
    end
  end
  # Make a path for the provided QS::QSObject
  def path_for obj, type = nil
    path(*get_qs_segments(obj, type))
  end
  # Make a path for the provided QS::QSObject
  def url_for obj, type = nil
    url(*get_qs_segments(obj, type))
  end
  # Build an array of string path segments for an object appropriate as path segments
  # 
  # [obj] Object, usually a QS::QSObject for which a path is to be generated
  # [type] optional string suffix to append to path segments
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