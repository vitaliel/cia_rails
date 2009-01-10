#
# Author: Vitalie Lazu <vitalie.lazu@gmail.com>
# Date: Sat, 10 Jan 2009 16:12:43 +0200
#

require 'yaml'

require 'cia_rails/command'
require 'cia_rails/vcs'
require 'cia_rails/builder'

module CiaRails
  class << self
    def build(conf_dir = "/etc/cia_rails")
      conf_file = File.join(conf_dir, 'cia_rails.yml')
      config = {:work_dir => '/var/tmp/cia_rails'}

      if test ?f, conf_file
        config.update(YAML.load_file(conf_file))
      end

      for project_conf_file in Dir["#{conf_dir}/*_project.yml"]
        builder = CiaRails::Builder.new(YAML.load_file(project_conf_file))
        builder.work_dir = config[:work_dir]
        builder.build
      end
    end
  end
end
