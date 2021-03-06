#!/bin/sh
exec ruby -S -x $0 "$@"
#!ruby
# coding: utf-8

##### require
require 'yaml'
require 'optparse'
require 'fileutils'
require 'pp'

if RUBY_VERSION >= '1.9.2'
  require_relative 'lib/config.rb'
  require_relative 'lib/func.rb'
  require_relative 'lib/init.rb'
  require_relative 'lib/targetwrapper.rb'
else
  require File.expand_path(File.dirname(__FILE__) + '/lib/config.rb')
  require File.expand_path(File.dirname(__FILE__) + '/lib/func.rb')
  require File.expand_path(File.dirname(__FILE__) + '/lib/init.rb')
  require File.expand_path(File.dirname(__FILE__) + '/lib/targetwrapper.rb')
end

##### option parse
option = {}
OptionParser.new do |opt|
  opt.on('-H', '--hosts=VALUE', 'The host list separated by a comma') {|v| option[:hosts] = v}
  opt.on('-f', '--file=VALUE', 'input file (Required)') {|v| option[:input_file] = v}
  opt.parse!(ARGV)
end
pp option if $DEBUG

if option[:input_file] == nil
  puts "ERROR: option"
  puts "\t--file <input file>"
  exit 1
end
if option[:hosts] != nil
  targets = option[:hosts].split(',')
else
  targets = ['localhost']
end

##### configuration
work_dir = File.expand_path(File.dirname(__FILE__))
Dir.chdir(work_dir)
if work_dir == '/'
  puts "ERROR: This script do not suppport run on root(/)."
  exit 1
end

# read input file
input_data = YAML.load_file(option[:input_file])
pp input_data if $DEBUG

# read config file
config_list = ["default.yaml", "customize.yaml"]
config_list.map! { |name| File.join(work_dir, "conf", name) }
config = read_config_file(config_list)
pp config if $DEBUG

##### target open
targets.each do |target|
  puts '+' * 50
  puts " #{target}"
  puts '+' * 50
  begin
    server = TargetWrapper.new
    server.set_puppet_path(config['puppet']['path'])
    server.set_facter_path(config['facter']['path'])
    server.open(target, config['ssh']['user'], config['ssh']['options'])

    ##### scan uid
    user_id_hash = {}
    if config['resource']['file']['user_name'] == true
    puts 'create uid list'
    server.run("cat /etc/passwd").each_line do |line|
      user_info = line.split(':')
      user_id_hash[user_info[2]] = user_info[0]
    end
    end
    pp user_id_hash if config["verbose"]

    ##### scan gid
    group_id_hash = {}
    if config['resource']['file']['group_name'] == true
    puts 'create gid list'
    server.run("cat /etc/group").each_line do |line|
      group_info = line.split(':')
      group_id_hash[group_info[2]] = group_info[0]
    end
    end
    pp group_id_hash if config["verbose"]

    ##### create output directory
    puts '-' * 50
    puts 'create output directory - '
    puts puppet_dir = File.join(work_dir, 'receive', target)
    create_initial_directory(puppet_dir)

    ##### create initial puppet file
    puts '-' * 50
    puts 'create files - '
    create_initial_file(puppet_dir, config["verbose"])

    ##### create modules
    puts '-' * 50
    puts 'create modules - '

    hiera_value_hash = {}
    hiera_value_hash["classes"] = []
    input_data.each do |key, val|
    ##### class name
    puts '-'*3 + key
    if !val.kind_of?(Hash)
      puts 'Error : format error. skip.'
      next
    end
    class_name = key
    class_name = server.replace_facter(class_name, config['facter']['allow'], {:downcase => true, :space => false})
    if class_name.split('::').size != 2
      puts 'Error : format error. skip. ::'
      next
    end
    hiera_value_hash["classes"].push(class_name)

    module_dir, pp_name = class_name.split('::')
    module_dir = File.join(puppet_dir, 'modules', module_dir)
    pp_name += ".pp"
    puts pp_path = File.join(module_dir, 'manifests' , pp_name)

    ##### make class body
    class_body = ''
    params_list = []
    val.each do |resource, lists|
      #puts resource
      #pp lists
      case resource
      ##### user resource
      when "user" then
      lists.each do |user|
        ret = server.run("#{config['puppet']['path']} resource user #{user.gsub(' ', '')}")
        reject = config['resource']['user']['attributes']['reject']
        ret.each_line.reject { |line|
        is_match = false
        reject.each do |attributes|
          is_match = true if line =~ /\s*#{attributes}\s*=>\s*/
        end
        is_match
        }.each do|line|
        class_body += (' '*2 + line.chomp + "\n")
        end
        class_body += ("\n")
      end
      ##### group resource
      when "group" then
      lists.each do |group|
        ret = server.run("#{config['puppet']['path']} resource group #{group.gsub(' ', '')}")
        reject = config['resource']['group']['attributes']['reject']
        ret.each_line.reject { |line|
        is_match = false
        reject.each do |attributes|
          is_match = true if line =~ /\s*#{attributes}\s*=>\s*/
        end
        is_match
        }.each do|line|
        class_body += (' '*2 + line.chomp + "\n")
        end
        class_body += ("\n")
      end
      ##### file resource
      when "file" then
      lists.each do |file_info|
        if file_info.kind_of?(String)
        file = file_info
        content = "no_content"
        elsif file_info.kind_of?(Hash)
        file, content = file_info.flatten
        else
        puts "Error: file resource format"
        pp file_info
        end
    #        pp file
    #        pp content
        ret = server.run("#{config['puppet']['path']} resource file #{file.gsub(' ', '')}")
        content.gsub!(" ", "")
        is_complement_content_path = false
        if /.*=.*/ =~ content
        content_type = content.split('=')[0]
        content_path = content.split('=')[1]
        content_path.gsub!(/\\\"|\"|\'/, "")
        else
        content_type = content.gsub(" ", "")
        content_path = file.gsub(" ", "").gsub(/^\//, "#{class_name.split("::")[0]}/")
        is_complement_content_path = true
        end

        reject = config['resource']['file']['attributes']['reject']
        ret.each_line.reject { |line|
        is_match = false
        reject.each do |attributes|
          is_match = true if line =~ /\s*#{attributes}\s*=>\s*/
        end
        is_match
        }.each do|line|
        if /\s*owner\s*=>\s*'(\d+)',/ =~ line
          owner = user_id_hash.has_key?($1) ? user_id_hash[$1] : $1
          pre = line.match(/\s*owner\s*=>\s*'/)[0]
          post = line.match(/',$/)[0]
          line = pre + owner + post
        elsif /\s*group\s*=>\s*'(\d+)',/ =~ line
          group = group_id_hash.has_key?($1) ? group_id_hash[$1] : $1
          pre = line.match(/\s*group\s*=>\s*'/)[0]
          post = line.match(/',$/)[0]
          line = pre + group + post
        elsif /\s*content\s*=>\s*'.*',/ =~ line
          pre = line.match(/\s*content\s*=>\s*/)[0]
          post = line.match(/,$/)[0]

          if content_type == "template"
          if is_complement_content_path == true and /\.erb$/ !~ content_path
            content_path += ".erb"
          end
          template_parameter = config['resource']['file']['param_template']
          if template_parameter == true
            param_name = File.basename(file.gsub(" ", "")).gsub(/[\.\-]/, '_')+'_tmpl'
            file_dirname = File.dirname(file.gsub(" ", ""))
            while params_list.include?(param_name)
            if file_dirname == '/'
              puts "Error: #{file} was dupulicate"
              break
            end
            param_name = File.basename(file_dirname).gsub(/[\.\-]/, '_') + "_" + param_name
            file_dirname = File.dirname(file_dirname)
            end
            params_list.push(param_name)
            hiera_value_hash["#{class_name}::#{param_name}"] = server.replace_facter(content_path, config['facter']['allow'])
            line = pre + "template($#{param_name})" + post
          else
            line = pre + "template(\"" + content_path + "\")" + post
          end

          # template copy
          file_src = file.gsub(" ", "")
          module_name = content_path.gsub(/\/.*/, '')
          post_path = content_path.gsub(/^[^\/]*\//, '')
          file_dist = File.join(puppet_dir, 'modules', module_name, 'templates', post_path)
          file_dist = server.replace_facter(file_dist, config['facter']['allow'])

          FileUtils.mkdir_p (File.dirname(file_dist))
          puts "copy : #{file_src}"
          puts "  => : #{file_dist}"
          server.copy(file_src, file_dist)
          FileUtils.chmod("a+r", file_dist)
          elsif content_type == "source"
          pre.sub!("content", "source ")
          source_parameter = config['resource']['file']['param_source']
          if source_parameter == true
            param_name = File.basename(file.gsub(" ", "")).gsub(/[\.\-]/, '_')+'_src'
            file_dirname = File.dirname(file.gsub(" ", ""))
            while params_list.include?(param_name)
            if file_dirname == '/'
              puts "Error: #{file} was dupulicate"
              break
            end
            param_name = File.basename(file_dirname).gsub(/[\.\-]/, '_') + "_" + param_name
            file_dirname = File.dirname(file_dirname)
            end
            params_list.push(param_name)
            hiera_value_hash["#{class_name}::#{param_name}"] = server.replace_facter(content_path, config['facter']['allow'])
            line = pre + "\"puppet:///modules/" + "${#{param_name}}" + "\"" + post
          else
            line = pre + "\"puppet:///modules/" + content_path + "\"" + post
          end

          # source copy
          file_src = file.gsub(" ", "")
          module_name = content_path.gsub(/\/.*/, '')
          post_path = content_path.gsub(/^[^\/]*\//, '')
          file_dist = File.join(puppet_dir, 'modules', module_name, 'files', post_path)
          file_dist = server.replace_facter(file_dist, config['facter']['allow'])

          FileUtils.mkdir_p (File.dirname(file_dist))
          puts "copy : #{file_src}"
          puts "  => : #{file_dist}"
          server.copy(file_src, file_dist)
          FileUtils.chmod("a+r", file_dist)
          end
        end
        class_body += (' '*2 + line.chomp + "\n")
        end
        class_body += ("\n")
      end
      ##### service resource
      when "service" then
      lists.each do |service|
        ret = server.run("#{config['puppet']['path']} resource service #{service.gsub(' ', '')}")
        reject = config['resource']['service']['attributes']['reject']
        ret.each_line.reject { |line|
        is_match = false
        reject.each do |attributes|
          is_match = true if line =~ /\s*#{attributes}\s*=>\s*/
        end
        is_match
        }.each do|line|
        ensure_parameter = config['resource']['service']['param_ensure']
        if ensure_parameter == true
          if /\s*ensure\s*=>\s*'(.*)',/ =~ line
          ensure_val = $1
          param_name = service.gsub(" ", "").gsub(/[\.\-]/, '_')+'_ensure'
          params_list.push(param_name)
          hiera_value_hash["#{class_name}::#{param_name}"] = ensure_val
          pre = line.match(/\s*ensure\s*=>\s*/)[0]
          post = line.match(/,$/)[0]
          line = pre + "$#{param_name}" + post
          end
        end

        enable_parameter = config['resource']['service']['param_enable']
        if enable_parameter == true
          if /\s*enable\s*=>\s*'(.*)',/ =~ line
          enable_val = $1
          param_name = service.gsub(" ", "").gsub(/[\.\-]/, '_')+'_enable'
          params_list.push(param_name)
          hiera_value_hash["#{class_name}::#{param_name}"] = enable_val
          pre = line.match(/\s*enable\s*=>\s*/)[0]
          post = line.match(/,$/)[0]
          line = pre + "$#{param_name}" + post
          end
        end

        class_body += (' '*2 + line.chomp + "\n")
        end
        class_body += ("\n")
      end
      ##### package resource
      when "package" then
      lists.each do |package|
      ret = server.run("#{config['puppet']['path']} resource package #{package.gsub(' ', '')}")
      reject = config['resource']['package']['attributes']['reject']
      ret.each_line.reject { |line|
        is_match = false
        reject.each do |attributes|
        is_match = true if line =~ /\s*#{attributes}\s*=>\s*/
        end
        is_match
        }.each do|line|
        ensure_parameter = config['resource']['package']['param_ensure']
        if ensure_parameter == true
          if /\s*ensure\s*=>\s*'(.*)',/ =~ line
          ensure_val = $1
          param_name = package.gsub(" ", "").gsub(/[\.\-]/, '_')+'_ensure'
          params_list.push(param_name)
          hiera_value_hash["#{class_name}::#{param_name}"] = ensure_val
          pre = line.match(/\s*ensure\s*=>\s*/)[0]
          post = line.match(/,$/)[0]
          line = pre + "$#{param_name}" + post
          end
        end

        class_body += (' '*2 + line.chomp + "\n")
        end
        class_body += ("\n")
      end
      ##### yumrepo resource
      when "yumrepo" then
      lists.each do |yumrepo|
        ret = server.run("#{config['puppet']['path']} resource yumrepo #{yumrepo.gsub(' ', '')}")
        reject = config['resource']['yumrepo']['attributes']['reject']
        ret.each_line.reject { |line|
        is_match = false
        reject.each do |attributes|
          is_match = true if line =~ /\s*#{attributes}\s*=>\s*/
        end
        is_match
        }.each do|line|
        ensure_parameter = config['resource']['yumrepo']['param_ensure']
        if ensure_parameter == true
          if /\s*ensure\s*=>\s*'(.*)',/ =~ line
          ensure_val = $1
          param_name = yumrepo.gsub(" ", "").gsub(/[\.\-]/, '_')+'_ensure'
          params_list.push(param_name)
          hiera_value_hash["#{class_name}::#{param_name}"] = ensure_val
          pre = line.match(/\s*ensure\s*=>\s*/)[0]
          post = line.match(/,$/)[0]
          line = pre + "$#{param_name}" + post
          end
        end

        enabled_parameter = config['resource']['yumrepo']['param_enabled']
        if enabled_parameter == true
          if /\s*enabled\s*=>\s*'(.*)',/ =~ line
          enabled_val = $1
          param_name = yumrepo.gsub(" ", "").gsub(/[\.\-]/, '_')+'_enabled'
          params_list.push(param_name)
          hiera_value_hash["#{class_name}::#{param_name}"] = enabled_val
          pre = line.match(/\s*enabled\s*=>\s*/)[0]
          post = line.match(/,$/)[0]
          line = pre + "$#{param_name}" + post
          end
        end

        class_body += (' '*2 + line.chomp + "\n")
        end
        class_body += ("\n")
      end
      else
      puts "Error: not support resource #{resource}"
      pp lists
      end
    end

    ##### output class
    if config["verbose"]
      puts "class #{class_name} ("
      params_list.each do |param|
      puts " "*2 + "$#{param},"
      end
      puts ") {"
      puts ""
      puts class_body
      puts "}"
      puts ""
    end

    FileUtils.mkdir_p (File.dirname(pp_path))
    File::open(pp_path, "w") do |fio|
      fio.puts "class #{class_name} ("
      params_list.each do |param|
      fio.puts " "*2 + "$#{param},"
      end
      fio.puts ") {"
      fio.puts ""
      fio.puts class_body
      fio.puts "}"
      fio.puts ""
    end

    end

    ##### output hieradata
    puts '-' * 50
    puts 'create hieradata - '
    hostname = server.run("#{config['facter']['path']} hostname").chomp
    puts yaml_file = File.join(puppet_dir, 'hieradata', "#{hostname}.yaml")
    hiera_data = YAML.dump(hiera_value_hash)
    puts hiera_data if config["verbose"]
    File::open(yaml_file, "w") do |fio|
    fio.puts hiera_data
    end
  rescue => exc
    p exc
  ensure
    server.close
  end
  puts ''
end
