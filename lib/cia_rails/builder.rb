#
# Author: Vitalie Lazu <vitalie.lazu@gmail.com>
# Date: Sat, 10 Jan 2009 16:12:47 +0200
#

require 'fileutils'

class CiaRails::Builder
  class BuildError < StandardError;end

  attr_reader :project
  attr_accessor :work_dir, :state_file, :state_dir

  def initialize(prj)
    @project = prj
    reset_buffer
    @operation = "Build"
  end

  def reset_buffer
    @output = ""
  end

  def add_line(line)
    @output << line << "\n"
  end

  # Used to deploy to stage server
  def deploy
    @operation = "Deploy"

    prepare_local_dir do
      run_cmd "cap -q deploy"
      run_cmd "cap -q deploy:migrate"
      run_cmd "cap -q deploy:cleanup"
    end
  end

  # Verify tests
  def build
    prepare_local_dir do
      add_scm_log
      # TODO install new gems
      # TODO install new Debian packages
      ignore_logs { prepare_db }
      run_tests
    end
  end

  def prepare_local_dir # yields
    self.state_dir = File.join(work_dir, project[:name])
    self.state_file = File.join(state_dir, "state.yml")

    load_state if test ?f, state_file
    state = :ok

    begin
      # TODO if project dir does not exist, checkout project and create a default database.yml
      unless test ?d, project[:home_dir]
        g = CiaRails::Git.new(self)
        g.checkout(project[:scm_url], project[:home_dir])
      end

      Dir.chdir(project[:home_dir])
      ignore_logs { update_sources }

      if @vcs.changed?
        yield
      end
    rescue BuildError
      state = :failed
    ensure
      if @vcs && @vcs.changed?
        save_state(state)
        send_notifications(state)
      end
    end
  end

  def ignore_logs(&block)
    buf = @output.clone
    yield
    # if no exceptions
    @output = buf
  end

  def add_scm_log
    @vcs.logs
  end

  def load_state
    @config = YAML::load_file(state_file)
    @old_state = config[:state]
  end

  def config
    @config || {}
  end

  def save_state(state)
    FileUtils::mkdir_p(state_dir)
    number = Time.now.to_i

    @config ||= {}
    @config[:last_revision] = @vcs.revision
    @config[:state] = state
    @config[:number] = number

    if state == :ok
      config[:failed_rev] = nil
    elsif state == :failed && @config[:failed_rev].nil?
      # Save last rev when build failed
      @config[:failed_rev] = @config[:last_revision]
    end

    File.open(state_file, "w") do |f|
      f.write YAML.dump(@config)
    end

    @output_file = File.join(state_dir, "output_#{number}.txt")

    File.open(@output_file, "w") do |f|
      f.write @output
    end
  end

  def prepare_db
    dev = rails_config['development']

    run_cmd("mysqladmin drop -f \"#{dev['database']}\"", true)
    run_cmd("mysqladmin create \"#{dev['database']}\"")
    run_cmd("mysqladmin create \"#{rails_config['test']['database']}\"", true)
    run_cmd("rake db:migrate --trace")
  end

  def run_tests
    run_cmd("rake")
  end

  def send_notifications(event)
    subject = nil

    if event == @old_state
      # Do not send notifications if build state was not changed
      return
    end

    if event == :ok
      if @old_state == :failed
        subject = "#{@operation} is fixed"
      end
    elsif event == :failed
      subject = "#{@operation} failed"
    else
      raise "bad event"
    end

    if subject
      if @vcs.emails.include?(project[:qa_email])
        extra = ""
      else
        extra = "-c #{project[:qa_email]}"
      end

      emails = @vcs.pretty_emails.map { |item| "\"#{item}\""}.join ' '

      IO::popen("mail -s '[QA] [#{project[:name]}] #{subject}' #{extra} #{emails}", "w") do |io|
        io.write(@output)
      end
    end
  end

  def rails_config
    @rails_config ||= YAML::load_file("config/database.yml")
  end

  def update_sources
    if test ?d, '.git'
      @vcs = CiaRails::Git.new(self)
    elsif test ?d, '.svn'
      @vcs = CiaRails::Svn.new(self)
    else
      raise "Unknown source control management"
    end

    @vcs.last_revision = config[:last_revision]
    @vcs.update
  end

  def run_cmd(cmd, can_fail = false)
    @output << "$ #{cmd}\n"

    child = CiaRails::Command.new(cmd) do |buf|
      @output << buf
    end

    rez = child.wait

    if !can_fail && rez[1] != 0
      @output << "Command '#{cmd}' exited with status #{rez[1]}"
      raise BuildError
    end

    rez[1]
  end

  class << self
    def build(projects)
      for project in projects
        self.new(project).build
      end
    end
  end
end
