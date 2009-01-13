#
# Author: Vitalie Lazu <vitalie.lazu@gmail.com>
# Date: Sat, 10 Jan 2009 16:12:47 +0200
#

module CiaRails
  class Vcs
    attr_accessor :last_revision

    def initialize(parent)
      @parent = parent
    end

    def changed?
      last_revision != revision
    end

    # revision for HEAD
    def revision
      -1
    end

    # logs since last build
    def logs
    end
  end

  class Git < Vcs
    def update
      @parent.run_cmd("git pull")
    end

    def revision
      @revision ||= `git log -1`.split(/\n/)[0].split[1]
    end

    def checkout(repo_uri, dest_dir)
      @parent.run_cmd("git clone -q '#{repo_uri}' '#{dest_dir}'")
    end

    def logs
      cmd = "git whatchanged "

      if last_revision
        cmd << "\"#{last_revision}..HEAD\""
      else
        cmd << "-1"
      end

      @parent.run_cmd(cmd)
    end
  end

  class Svn < Vcs
    def update
      @parent.run_cmd("svn up")
    end

    def revision
      raise "Not implemented"
    end
  end
end
