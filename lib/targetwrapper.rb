# coding: utf-8
require 'fileutils'

class TargetWrapper

  def initialize
    @target = 'local'
  end

  def open()
  end
    
  def close()
  
  end

  def run(command)
    if @target == 'local'
      ret = `#{command}`
    else
    
    end
    return ret
  end
  
  def copy(src, dist)
    if @target == 'local'
      FileUtils.copy(src, dist)
    else
    
    end
  end

end
