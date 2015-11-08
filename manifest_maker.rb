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
pp input_data if $DEBGU
config_data = YAML.load_file(config_file_path)
pp config_data if $DEBGU

opt_verbose = config_data.has_key?("verbose") ? config_data["verbose"] : false

begin
  use_user_name = config_data['resource']['file']['user_name']
rescue
  use_user_name = false
ensure
end
begin
  use_group_name = config_data['resource']['file']['group_name']
rescue
  use_group_name = false
ensure
end
begin
  facter_allows_list = config_data['facter']['allow']
rescue
  facter_allows_list = ['hostname']
ensure
end
#pp facter_allows_list

reject_attributes = {}
begin
  reject_attributes['user'] = config_data['resource']['user']['attributes']['reject']
rescue
  reject_attributes['user'] = []
ensure
end
begin
  reject_attributes['group'] = config_data['resource']['group']['attributes']['reject']
rescue
  reject_attributes['group'] = []
ensure
end
begin
  reject_attributes['file'] = config_data['resource']['file']['attributes']['reject']
rescue
  reject_attributes['file'] = []
ensure
end
begin
  reject_attributes['service'] = config_data['resource']['service']['attributes']['reject']
rescue
  reject_attributes['service'] = []
ensure
end
begin
  reject_attributes['package'] = config_data['resource']['package']['attributes']['reject']
rescue
  reject_attributes['package'] = []
ensure
end

##### scan uid
user_id_hash = {}
if use_user_name == true
  puts 'create uid list'
  `cat /etc/passwd`.each_line do |line|
    user_info = line.split(':')
    user_id_hash[user_info[2]] = user_info[0]
  end
end
pp user_id_hash if opt_verbose

##### scan gid
group_id_hash = {}
if use_group_name == true
  puts 'create gid list'
  `cat /etc/group`.each_line do |line|
    group_info = line.split(':')
    group_id_hash[group_info[2]] = group_info[0]
  end
end
pp group_id_hash if opt_verbose

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
puts file_contents if opt_verbose
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
puts file_contents if opt_verbose
File::open(File.join(puppet_dir, 'hiera.yaml'), 'w') do |fio|
  fio.puts file_contents
end

puts File.join(puppet_dir, 'manifests/site.pp')
file_contents = <<"EOS"
node default {
  hiera_include("classes")
}
EOS
puts file_contents if opt_verbose
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
  class_name = replace_facter(class_name, facter_allows_list, {:downcase => true, :space => false})
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
        ret.each_line.reject { |line|
          is_match = false
          reject_attributes['user'].each do |attributes|
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
        ret.each_line.reject { |line|
          is_match = false
          reject_attributes['group'].each do |attributes|
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
        if /.*=.*/ =~ content
          content_type = content.split('=')[0]
          content_path = content.split('=')[1]
          content_path.gsub!(/\\\"|\"|'/, "")
        else
          content_type = content.gsub(" ", "")
          content_path = file.gsub(" ", "").gsub(/^\//, "#{class_name.split("::")[0]}/")
        end
        if config_data['resource']['file'] != nil and
           config_data['resource']['file'].has_key?("param_template")
          enable_param_template = config_data['resource']['file']['param_template']
        else
          enable_param_template = false
        end
        if config_data['resource']['file'] != nil and 
           config_data['resource']['file'].has_key?("param_source")
          enable_param_source = config_data['resource']['file']['param_source']
        else
          enable_param_source = false
        end
        ret.each_line.reject { |line|
          is_match = false
          reject_attributes['file'].each do |attributes|
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
              if enable_param_template == true
                param_name = File.basename(file.gsub(" ", "")).gsub(".", "_")+'_tmpl'
                file_dirname = File.dirname(file.gsub(" ", ""))
                while params_list.include?(param_name)
                  if file_dirname == '/'
                    puts "Error: #{file} was dupulicate"
                    break
                  end
                  param_name = File.basename(file_dirname).gsub(".", "_") + "_" + param_name
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
              file_dist = replace_facter(file_dist, facter_allows_list)

              FileUtils.mkdir_p (File.dirname(file_dist))
              puts "copy : #{file_src}"               
              puts "  => : #{file_dist}"
              FileUtils.copy(file_src, file_dist)
              
            elsif content_type == "source"
              pre.sub!("content", "source ")
              if enable_param_source == true
                param_name = File.basename(file.gsub(" ", "")).gsub(".", "_")+'_src'
                file_dirname = File.dirname(file.gsub(" ", ""))
                while params_list.include?(param_name)
                  if file_dirname == '/'
                    puts "Error: #{file} was dupulicate"
                    break
                  end
                  param_name = File.basename(file_dirname).gsub(".", "_") + "_" + param_name
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
              file_dist = replace_facter(file_dist, facter_allows_list)

              FileUtils.mkdir_p (File.dirname(file_dist))
              puts "copy : #{file_src}"               
              puts "  => : #{file_dist}"
              FileUtils.copy(file_src, file_dist)
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
        if config_data['resource']['service'] != nil and
           config_data['resource']['service'].has_key?("param_ensure")
          enable_param_ensure = config_data['resource']['service']['param_ensure']
        else
          enable_param_ensure = false
        end
        if config_data['resource']['service'] != nil and 
           config_data['resource']['service'].has_key?("param_enable")
          enable_param_enable = config_data['resource']['service']['param_enable']
        else
          enable_param_enable = false
        end
        ret.each_line.reject { |line|
          is_match = false
            reject_attributes['service'].each do |attributes|
            is_match = true if line =~ /\s*#{attributes}\s*=>\s*/
          end
          is_match
        }.each do|line|

          if enable_param_ensure == true
            if /\s*ensure\s*=>\s*'(.*)',/ =~ line
              ensure_val = $1
              param_name = service.gsub(" ", "")+'_ensure'
              params_list.push(param_name)
              hiera_value_hash["#{class_name}::#{param_name}"] = ensure_val
              pre = line.match(/\s*ensure\s*=>\s*/)[0]
              post = line.match(/,$/)[0]
              line = pre + "$#{param_name}" + post
            end
          end

          if enable_param_enable == true
            if /\s*enable\s*=>\s*'(.*)',/ =~ line
              enable_val = $1
              param_name = service.gsub(" ", "")+'_enable'
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
        if config_data['resource']['package'] != nil and
           config_data['resource']['package'].has_key?("param_ensure")
          enable_param_ensure = config_data['resource']['package']['param_ensure']
        else
          enable_param_ensure = false
        end
        ret.each_line.reject { |line|
          is_match = false
          reject_attributes['package'].each do |attributes|
            is_match = true if line =~ /\s*#{attributes}\s*=>\s*/
          end
          is_match
        }.each do|line|

          if enable_param_ensure == true
            if /\s*ensure\s*=>\s*'(.*)',/ =~ line
              ensure_val = $1
              param_name = package.gsub(" ", "")+'_ensure'
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
  if opt_verbose
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
puts hiera_data if opt_verbose
File::open(yaml_file, "w") do |fio|
  fio.puts hiera_data
end
