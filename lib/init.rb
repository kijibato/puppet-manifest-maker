# coding: utf-8

def create_initial_directory(puppet_dir)
  puts FileUtils.mkdir_p (File.join(puppet_dir, 'hieradata'))
  puts FileUtils.mkdir_p (File.join(puppet_dir, 'manifests'))
  puts FileUtils.mkdir_p (File.join(puppet_dir, 'modules'))
end

def create_initial_file(puppet_dir, verbose)
  contents_autosign_conf = <<"EOS"
*
EOS

  contents_hiera_yaml = <<"EOS"
---
:backends:
  - yaml
:yaml:
  :datadir: /etc/puppet/hieradata
:hierarchy:
  - "%{::hostname}"
  - default
EOS

  contents_site_pp = <<"EOS"
node default {
  Group <| |> -> User <| |>
  User <| |> -> Yumrepo <| |>
  Yumrepo <| |> -> Package <| |>
  Package <| |> -> File <| |>
  File <| |> -> Service <| |>
  
  hiera_include("classes")
}
EOS

  # autosign.conf
  puts File.join(puppet_dir, 'autosign.conf')
  puts contents_autosign_conf if verbose
  File::open(File.join(puppet_dir, 'autosign.conf'), 'w') do |fio|
    fio.puts contents_autosign_conf
  end

  # hiera.yaml
  puts File.join(puppet_dir, 'hiera.yaml')
  puts contents_hiera_yaml if verbose
  File::open(File.join(puppet_dir, 'hiera.yaml'), 'w') do |fio|
    fio.puts contents_hiera_yaml
  end

  # site.pp
  puts File.join(puppet_dir, 'manifests', 'site.pp')
  puts contents_site_pp if verbose
  File::open(File.join(puppet_dir, 'manifests', 'site.pp'), 'w') do |fio|
    fio.puts contents_site_pp
  end
end
