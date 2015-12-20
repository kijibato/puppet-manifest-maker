# coding: utf-8
require 'fileutils'
begin
  require 'rubygems'
  require 'net/ssh'
  require 'net/scp'
rescue LoadError
end

class TargetWrapper

  def initialize()
    @target = 'local'
  end

  def open(hostname='localhost', user='root', options={})
    if hostname == 'localhost'
      @target = 'local'
    else
      @target = hostname
      @ssh = Net::SSH.start(@target, user, options)
    end
  end
  
  def close()
    if @target != 'local'
      @ssh.close()
    end
  end

  def run(command)
    if @target == 'local'
      ret = `#{command}`
    else
      ret = @ssh.exec! command
    end
    return ret
  end
  
  def copy(src, dist)
    if @target == 'local'
      FileUtils.copy(src, dist)
    else
      @ssh.scp.download!(src, dist)
    end
  end

end
