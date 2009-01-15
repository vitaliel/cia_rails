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
      print_logs
    end

    def print_logs
      unless @commits
        param = "-1"

        if last_revision
          param = "#{last_revision}..HEAD"
        end

        @commits = changed_files(param)
      end

      @parent.add_line "Changes since last build\n#{'-' * 75}"

      for commit in @commits
        @parent.add_line "#{commit[:name]} committed #{commit[:sha]}"
        @parent.add_line "Comment: #{commit[:subject]}"
        @parent.add_line "#{@parent.project[:changeset_url]}#{commit[:sha]}"
        @parent.add_line "Affected files:"

        for file in commit[:files]
          @parent.add_line "  #{file}"
        end

        @parent.add_line "-" * 75
      end
    end

    def emails
      @commits.map {|c| c[:email] }.uniq
    end

    def pretty_emails
      all = []
      rez = []

      @commits.each do |c|
        unless all.include?(c[:email])
          rez << "#{c[:name]} <#{c[:email]}>"
          all << c[:email]
        end
      end

      rez
    end

    # Runs git whatchanged and return parsed data as array
    # *args other arguments to pass to git command
    # Return array if hashes: [{:date=>"2009-01-15 18:53:37 +0200", :subject=>"Updated doc for git tool setup", :email=>"vitalie.lazu@gmail.com", :files=>["M doc/setup_git_tools.txt"], :name=>"Vitalie Lazu", :sha=>"c523c70"}]
    def changed_files(*args)
      cmd = "git whatchanged --pretty=format:'%h,%ci,%ce,%cn%n%s' "
      cmd << args.join(' ')

      rez = []
      next_data = :commit
      info = nil

      IO::popen(cmd) do |f|
        while line = f.gets
          line.chomp!

          case next_data
          when :subject
            info[:subject] = line
            next_data = :files
          when :files
            old_mode, _, _, _, mode, file = line.split(/\s+/, 6)

            if old_mode =~ /^:/
              info[:files] ||= []
              info[:files] << "#{mode} #{file}"
            else
              next_data = :commit
            end
          when :commit
            rez << info if info
            info = {}
            info[:sha], info[:date], info[:email], info[:name] = line.split(',', 4)
            next_data = :subject
          else
            next_data = :commit
          end
        end
      end

      rez << info if info

      rez
    end
  end # end git vcs

  class Svn < Vcs
    def update
      @parent.run_cmd("svn up")
    end

    def revision
      @revision ||= @parent.run_cmd("svn info | grep Revision | awk '{print $2}'")
    end
  end
end
