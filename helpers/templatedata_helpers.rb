require 'lib/app'

# Helper methods to access data exposed to templates in bundle_reader.rb
module TemplateDataHelpers
  # Fetch the template data extension from App
  def load_template_data!
    @template_data = App.require_one :template_data
  end
  # Template data extension from App
  def template_data
    @template_data || load_template_data!
  end
  # Shortcut to template_data[:config]
  def config
    template_data[:config] || {}
  end
end
