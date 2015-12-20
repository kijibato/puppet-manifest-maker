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

  def replace_facter(src_str, allows_list, opt=nil)
    facter_keys = src_str.scan(/%\{::([^\}]*)\}/)
    if facter_keys.empty? != true
      # get facter infomation
      facter_hash = {}
      facter_keys.flatten.each do |key|
        if allows_list.include?(key)
          facter_hash[key] = run("facter #{key}").chomp
          facter_hash[key].downcase! if opt != nil and opt.has_key?(:downcase) and opt[:downcase]
          facter_hash[key].gsub!(/[\.\s]/, "_") if opt != nil and opt.has_key?(:space) and !opt[:space]
        end
      end
      # replace facter
      facter_hash.each do |key, val|
        src_str = src_str.gsub(/%\{::#{key}\}/, val)
      end
    end
    return src_str
  end
end
