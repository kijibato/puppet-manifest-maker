# coding: utf-8

def replace_facter(src_str, allows_list, opt=nil)
  facter_keys = src_str.scan(/%\{::([^\}]*)\}/)
  if facter_keys.empty? != true
    # get facter infomation
    facter_hash = {}
    facter_keys.flatten.each do |key|
      if allows_list.include?(key)
        facter_hash[key] = `facter #{key}`.chomp
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
