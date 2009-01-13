#
# Author: Vitalie Lazu <vitalie.lazu@gmail.com>
# Date: Thu, 27 Nov 2008 16:10:04 +0200
#

require 'thread'

module CiaRails;end

class CiaRails::Command
  #
  def initialize(cmd, delay = 1, &block)
    @cb = block
    @cmd = cmd
    @parent_to_child_read, @parent_to_child_write = IO.pipe
    @child_to_parent_read, @child_to_parent_write = IO.pipe
    @finish = false

    @child_pid = fork do
      @parent_to_child_write.close
      @child_to_parent_read.close
      $stdin.reopen(@parent_to_child_read)
      $stdout.reopen(@child_to_parent_write)
      $stderr.reopen(@child_to_parent_write)
      exec(@cmd)
    end

    @read_th = Thread.new do
      while true
        if r = select([@child_to_parent_read], nil, nil, 1.5)
          data = @child_to_parent_read.read(1)
          @cb.call data
        end

        break if @finish && r.nil?
      end
    end
  end

  def puts(str)
    @parent_to_child_write.puts(str)
  end

  def wait
    r = Process.wait2
    @finish = true
    @read_th.join if @read_th

    r
  end

  def kill
    @child_pid.kill
  end
end
