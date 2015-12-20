# coding: utf-8

def read_config_file(config_list)
  config = {}
  config_list.each do |path|
    if File.exist?(path)
      tmp_config = YAML.load_file(path)
      config.deep_merge!(tmp_config)
    end
#    pp config if $DEBUG
  end
  return config
end
