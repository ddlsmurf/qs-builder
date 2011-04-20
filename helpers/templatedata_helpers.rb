require 'lib/app'

module TemplateDataHelpers
  def load_template_data!
    @template_data = App.require_one :template_data
  end
  def template_data
    @template_data || load_template_data!
  end
  def config
    template_data[:config] || {}
  end
end
