#!/bin/sh
exec ruby -S -x $0 "$@"
#!ruby
# coding: utf-8

##### require
require 'yaml'
require 'optparse'
require 'fileutils'
require 'pp'

require './lib/facter.rb'
require './lib/func.rb'

##### option parse
params = ARGV.getopts('', 'file:')
puts params if $DEBUG

if params['file'] == nil
  puts "ERROR: option"
  puts "\t--file <input file>"
  exit 1
else
  input_file_name = params['file']
end

##### configuration
hostname = `facter hostname`.chomp
work_dir = File.expand_path(File.dirname(__FILE__))
Dir.chdir(work_dir)
if work_dir == '/'
  puts "ERROR: This script do not suppport run on root(/)."
  exit 1
end

config_file_path = File.join(work_dir, "config.yaml")

input_data = YAML.load_file(input_file_name)
pp input_data if $DEBUG
config = YAML.load_file(config_file_path)
pp config if $DEBUG

# read customized config
custom_config_file_path = File.join(work_dir, "customize.yaml")
if File.exist?(custom_config_file_path)
  custom_config = YAML.load_file(custom_config_file_path)
  config.deep_merge!(custom_config)
end
pp config if $DEBUG



##### scan uid
user_id_hash = {}
if config['resource']['file']['user_name'] == true
  puts 'create uid list'
  `cat /etc/passwd`.each_line do |line|
    user_info = line.split(':')
    user_id_hash[user_info[2]] = user_info[0]
  end
end
pp user_id_hash if config["verbose"]

##### scan gid
group_id_hash = {}
if config['resource']['file']['group_name'] == true
  puts 'create gid list'
  `cat /etc/group`.each_line do |line|
    group_info = line.split(':')
    group_id_hash[group_info[2]] = group_info[0]
  end
end
pp group_id_hash if config["verbose"]

##### create output directory
puts '+' * 50
puts 'create output directory - '

puts puppet_dir = File.join(work_dir, 'build/etc/puppet')
puts FileUtils.mkdir_p (File.join(puppet_dir, 'hieradata'))
puts FileUtils.mkdir_p (File.join(puppet_dir, 'manifests'))
puts FileUtils.mkdir_p (File.join(puppet_dir, 'modules'))

##### create initial puppet file
puts '+' * 50
puts 'create files - '
puts File.join(puppet_dir, 'autosign.conf')
file_contents = <<"EOS"
*
EOS
puts file_contents if config["verbose"]
File::open(File.join(puppet_dir, 'autosign.conf'), 'w') do |fio|
  fio.puts file_contents
end

puts File.join(puppet_dir, 'hiera.yaml')
file_contents = <<"EOS"
---
:backends:
  - yaml
:yaml:
  :datadir: /etc/puppet/hieradata
:hierarchy:
  - "%{::hostname}"
  - default
EOS
puts file_contents if config["verbose"]
File::open(File.join(puppet_dir, 'hiera.yaml'), 'w') do |fio|
  fio.puts file_contents
end

puts File.join(puppet_dir, 'manifests/site.pp')
file_contents = <<"EOS"
node default {
  Group <| |> -> User <| |>
  User <| |> -> Package <| |>
  Package <| |> -> File <| |>
  File <| |> -> Service <| |>
  
  hiera_include("classes")
}
EOS
puts file_contents if config["verbose"]
File::open(File.join(puppet_dir, 'manifests/site.pp'), 'w') do |fio|
  fio.puts file_contents
end

##### create modules
puts '+' * 50
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
  class_name = replace_facter(class_name, config['facter']['allow'], {:downcase => true, :space => false})
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
        ret = `puppet resource user #{user.gsub(" ", "")}`
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
        ret = `puppet resource group #{group.gsub(" ", "")}`
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
        ret = `puppet resource file #{file.gsub(" ", "")}`
        content.gsub!(" ", "")
        is_complement_content_path = false
        if /.*=.*/ =~ content
          content_type = content.split('=')[0]
          content_path = content.split('=')[1]
          content_path.gsub!(/\\\"|\"|'/, "")
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
                hiera_value_hash["#{class_name}::#{param_name}"] = content_path
                line = pre + "template($#{param_name})" + post
              else
                line = pre + "template(\"" + content_path + "\")" + post
              end
              
              # template copy
              file_src = file.gsub(" ", "")
              module_name = content_path.gsub(/\/.*/, '')
              post_path = content_path.gsub(/^[^\/]*\//, '')
              file_dist = File.join(puppet_dir, 'modules', module_name, 'templates', post_path)
              file_dist = replace_facter(file_dist, config['facter']['allow'])

              FileUtils.mkdir_p (File.dirname(file_dist))
              puts "copy : #{file_src}"               
              puts "  => : #{file_dist}"
              FileUtils.copy(file_src, file_dist)
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
                hiera_value_hash["#{class_name}::#{param_name}"] = content_path
                line = pre + "\"puppet:///modules/" + "${#{param_name}}" + "\"" + post
              else
                line = pre + "\"puppet:///modules/" + content_path + "\"" + post
              end

              # source copy
              file_src = file.gsub(" ", "")
              module_name = content_path.gsub(/\/.*/, '')
              post_path = content_path.gsub(/^[^\/]*\//, '')
              file_dist = File.join(puppet_dir, 'modules', module_name, 'files', post_path)
              file_dist = replace_facter(file_dist, config['facter']['allow'])

              FileUtils.mkdir_p (File.dirname(file_dist))
              puts "copy : #{file_src}"               
              puts "  => : #{file_dist}"
              FileUtils.copy(file_src, file_dist)
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
        ret = `puppet resource service #{service.gsub(" ", "")}`
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
        ret = `puppet resource package #{package.gsub(" ", "")}`
        reject = config['resource']['package']['attributes']['reject']
        ret.each_line.reject { |line|
          is_match = false
          reject.each do |attributes|
            is_match = true if line =~ /\s*#{attributes}\s*=>\s*/
          end
          is_match
        }.each do|line|
          enable_parameter = config['resource']['package']['param_ensure']
          if enable_parameter == true
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
puts '+' * 50
puts 'create hieradata - '
puts yaml_file = File.join(puppet_dir, 'hieradata', "#{hostname}.yaml")
hiera_data = YAML.dump(hiera_value_hash)
puts hiera_data if config["verbose"]
File::open(yaml_file, "w") do |fio|
  fio.puts hiera_data
end
