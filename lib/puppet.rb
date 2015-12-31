# coding: utf-8

def copy_puppet_file_by_patch_data(patch_data_hash, src_dir, dist_dir)
  # -- listing class
  class_list = []
  relative_file_path = []

  patch_data_hash.each do |patch_key, patch_value|
  	# parse classes
    if patch_key == 'classes'
      patch_value.each do |classes_set|
        if classes_set.has_key?('value')
          classes_set['value'].each do |module_class|
            class_list.push(module_class)
          end
        end
      end
    # parse parameter
    else
      # listing class
      split_class_name = patch_key.split('::')
      class_parameter = split_class_name.pop
      module_class = split_class_name.join('::')
      class_list.push(module_class)
      # listing file
      if /_tmpl$/ =~ class_parameter or /_src$/ =~ class_parameter
        patch_value.each do |node_value|
          if node_value.has_key?("value")
            tmp_path = node_value["value"].split('/')
            module_name = tmp_path.shift
            if /_tmpl$/ =~ class_parameter
              type = 'templates'
         	else # if /_src$/ =~ class_parameter
         	  type = 'files'
         	end
            relative_file_path.push(File.join("modules", module_name, type, tmp_path))
          end
        end
      end
    end
  end
  class_list.uniq!
  relative_file_path.uniq!
  pp class_list if $DEBUG
  pp relative_file_path if $DEBUG

  # convert class name to class path
  relative_class_path = []
  if class_list.size > 0
    class_list.each do |module_class|
      split_class_name = module_class.split('::')
      module_name = split_class_name.shift
      class_path = File.join("modules", module_name, "manifests")
      while split_class_name.size > 1
        class_path = File.join(class_path, split_class_name.shift)
      end
      class_path = File.join(class_path, split_class_name.shift + '.pp')
      relative_class_path.push(class_path)
    end
  end
  relative_class_path.uniq!
  pp relative_class_path if $DEBUG

  # -- copy class and file
  (relative_class_path + relative_file_path).each do |path|
    src = File.join(src_dir, path)
    dist = File.join(dist_dir, path)
    if File.directory?(File.dirname(dist)) == false
      puts FileUtils.mkdir_p (File.dirname(dist))
    end
    FileUtils.copy(src, dist)
    FileUtils.chmod("a+r", dist)
  end

end
