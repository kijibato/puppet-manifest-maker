#!/bin/sh
exec ruby -S -x $0 "$@"
#!ruby
# coding: utf-8

##### require
require 'yaml'
require 'optparse'
require 'readline'
require 'fileutils'
require 'pp'

if RUBY_VERSION >= '1.9.2'
  require_relative 'lib/config.rb'
  require_relative 'lib/func.rb'
  require_relative 'lib/init.rb'
#  require_relative 'lib/targetwrapper.rb'
else
  require File.expand_path(File.dirname(__FILE__) + '/lib/config.rb')
  require File.expand_path(File.dirname(__FILE__) + '/lib/func.rb')
  require File.expand_path(File.dirname(__FILE__) + '/lib/init.rb')
#  require File.expand_path(File.dirname(__FILE__) + '/lib/targetwrapper.rb')
end

##### option parse
params = ARGV.getopts('', 'mode:', 'nodes:', 'keys:', 'file:', 'from:')
puts params if $DEBUG

if params['mode'] == nil or 
  (params['mode'] != 'init' and
   params['mode'] != 'select' and
   params['mode'] != 'update' and
   params['mode'] != 'delete')
  puts "ERROR: mode option"
  puts "\t--mode init|select|update|delete"
  exit 1
end

if (params['mode'] == 'select' and params['from'] == nil) or
   (params['mode'] != 'select' and params['from'] != nil)
  puts "ERROR: select option"
  puts "\t--mode select --from DIRECTORY"
  exit 1
end

##### configuration
work_dir = File.expand_path(File.dirname(__FILE__))

# read config file
config_list = ["default.yaml", "customize.yaml"]
config_list.map! { |name| File.join(work_dir, "conf", name) }
config = read_config_file(config_list)
pp config if $DEBUG

# create directory
build_dir = File.join(work_dir, "build", "master")
puts FileUtils.mkdir_p (build_dir)
create_initial_directory(build_dir)

if params["from"] != nil
  source_dir = File.join(work_dir, params["from"], "hieradata")
  hiera_file_list = Dir.glob(File.join(source_dir, "./**/*.yaml"))
else
  source_dir = build_dir
  hiera_file_list = Dir.glob(File.join(build_dir, "./**/*.yaml"))
end
pp hiera_file_list

if params['file'] != nil
  patch_file = params['file']
else
  patch_file = File.join(work_dir, 'patch.yaml')
end

hiera_data_hash = {}
hiera_file_list.each do |file_name|
#  hiera_data_hash[file_name] = YAML.load_file(file_name)
  puts file_name if $DEBUG
  node = file_name.gsub(source_dir, '').gsub(/^\/*\.\/(.+)\.yaml$/, '\1')
  hiera_data_hash[node] = YAML.load_file(file_name)
end

case params['mode']
when 'init'
  ##### create initial puppet file
  puts '-' * 50
  puts 'create files - '
  create_initial_file(build_dir, config["verbose"])
when 'select'
  pp hiera_data_hash if $DEBUG
  if params['nodes'] != nil
    regexp = Regexp.union(params['nodes'].split(','))
    hiera_data_hash.select! { |node, hiera_data| node =~ regexp}
  end
  if params['keys'] != nil
    regexp = Regexp.union(params['keys'].split(','))
    hiera_data_hash.each do |node, hiera_data|
      if params['keys'].include?('classes')
        hiera_data.select! { |key, value| key =~ regexp }
      else
        hiera_data.select! { |key, value| 
          if key == 'classes'
            value.select!{ |class_name| class_name =~ regexp }
            value.empty? ? false : true
          else
            key =~ regexp
          end
        }
      end
    end
  end
  pp hiera_data_hash if $DEBUG
  
  patch_data_hash = {}
  hiera_data_hash.each do |node, hiera_data|
    hiera_data.each do |key, val|
      if patch_data_hash.has_key? (key)
        is_equal_val = false
        patch_data_hash[key].each do | nodes_val |
          if nodes_val['value'] == val
            nodes_val['nodes'].push(node)
            is_equal_val = true
          end
        end
        if is_equal_val == false
          patch_data_hash[key].push({ 'nodes' => [node], 'value' => val })
        end
      else
        patch_data_hash[key] = [{ 'nodes' => [node], 'value' => val }]
      end
    end
  end
  
  puts '=' * 50 if $DEBUG
  pp patch_data_hash if $DEBUG
  
  puts '=' * 50 if $DEBUG
  str = YAML.dump(patch_data_hash)
  puts str
  File::open(patch_file, 'w') do |file|
    file.puts str
  end
when 'update'
  input = Readline.readline("Does hieradata update by #{patch_file}y/n[n]? : ")
  if input.chomp.downcase != 'y'
    puts 'cancel'
    exit 0
  end
  patch_data_hash = YAML.load_file(patch_file)

  pp patch_data_hash if $DEBUG
  update_val_count = 0
  patch_data_hash.each do |key, list|
   list.each do |data|
     data["nodes"].each do |node|
       puts node if $DEBUG
       pp hiera_data_hash if $DEBUG
       hiera_data_hash[node] = {} if hiera_data_hash[node] == nil
       pp hiera_data_hash[node] if $DEBUG
       pp hiera_data_hash[node][key] if $DEBUG
       pp data["value"] if $DEBUG
       if hiera_data_hash[node][key] != data["value"]
         is_update = false
         if key == 'classes'
           if hiera_data_hash[node][key] != nil
             if (data["value"] & hiera_data_hash[node][key]).size != data["value"].size
               hiera_data_hash[node][key].concat(data["value"])
               hiera_data_hash[node][key].uniq!
               is_update = true
            end
           else
             hiera_data_hash[node][key] = data["value"]
             is_update = true
          end
         else
           hiera_data_hash[node][key] = data["value"]
           is_update = true
         end
         update_val_count += 1 if is_update
       end
      end
    end
  end

  hiera_data_hash.each do |node, hiera_data|
    file_name = './' + node + '.yaml'
    FileUtils.mkdir_p(File.dirname(file_name)) unless FileTest::directory?(File.dirname(file_name))
    str = YAML.dump(hiera_data)
    puts file_name if $DEBUG
    puts str if $DEBUG
    File::open(file_name, 'w') do |file|
      file.puts str
    end
  end

   puts "update " + update_val_count.to_s + " values."
when 'delete'

  input = Readline.readline("Does hieradata delete by #{patch_file}y/n[n]? : ")
  if input.chomp.downcase != 'y'
    puts 'cancel'
    exit 0
  end
  patch_data_hash = YAML.load_file(patch_file)

  pp patch_data_hash if $DEBUG
  delete_val_count = 0
  patch_data_hash.each do |key, list|
   list.each do |data|
     data["nodes"].each do |node|
       puts node if $DEBUG
       pp hiera_data_hash if $DEBUG
       
       pp hiera_data_hash[node] if $DEBUG
       pp hiera_data_hash[node][key] if $DEBUG
       pp data["value"] if $DEBUG
       
       if key != 'classes'
         hiera_data_hash[node].delete(key)
         delete_val_count += 1         
       else
         data["value"].each do |class_name|
           before_size = hiera_data_hash[node]['classes'].size
           ret = hiera_data_hash[node]['classes'].delete(class_name)
           after_size = hiera_data_hash[node]['classes'].size
           delete_val_count += (before_size - after_size) if ret != nil
         end
       end
      end
    end
  end

  hiera_data_hash.each do |node, hiera_data|
    file_name = './' + node + '.yaml'
    FileUtils.mkdir_p(File.dirname(file_name)) unless FileTest::directory?(File.dirname(file_name))
    str = YAML.dump(hiera_data)
    puts file_name if $DEBUG
    puts str if $DEBUG
    File::open(file_name, 'w') do |file|
      file.puts str
    end
  end

  puts "delete " + delete_val_count.to_s + " values."
end
