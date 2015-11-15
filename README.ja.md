# puppet-manifest-maker

これはサーバの設定情報から、Puppetマニフェストを作成するスクリプトです。
設定済みのサーバー上で実行してください。
現時点では、user,group,file,package,serviceのみサポートしています。

## 実行環境

```
[root@web01 share]# uname -n
web01
[root@web01 share]# cat /etc/centos-release
CentOS Linux release 7.1.1503 (Core) 
[root@web01 share]# ruby --version
ruby 2.0.0p598 (2014-11-13) [x86_64-linux]
[root@web01 share]# facter puppetversion
3.8.4
[root@web01 share]# pwd
/share
```

## 実行例

```
[root@web01 share]# ruby manifest_maker.rb --file sample_input.yaml          
create uid list
{"0"=>"root",
 "1"=>"bin",
 "2"=>"daemon",
 "3"=>"adm",
 "4"=>"lp",
 "5"=>"sync",
 "6"=>"shutdown",
 "7"=>"halt",
 "8"=>"mail",
 "11"=>"operator",
 "12"=>"games",
 "14"=>"ftp",
 "99"=>"nobody",
 "52"=>"puppet",
 "74"=>"sshd",
 "1000"=>"guest",
 "48"=>"apache"}
create gid list
{"0"=>"root",
 "1"=>"bin",
 "2"=>"daemon",
 "3"=>"sys",
 "4"=>"adm",
 "5"=>"tty",
 "6"=>"disk",
 "7"=>"lp",
 "8"=>"mem",
 "9"=>"kmem",
 "10"=>"wheel",
 "11"=>"cdrom",
 "12"=>"mail",
 "15"=>"man",
 "18"=>"dialout",
 "19"=>"floppy",
 "20"=>"games",
 "30"=>"tape",
 "39"=>"video",
 "50"=>"ftp",
 "54"=>"lock",
 "63"=>"audio",
 "99"=>"nobody",
 "100"=>"users",
 "22"=>"utmp",
 "35"=>"utempter",
 "190"=>"systemd-journal",
 "52"=>"puppet",
 "999"=>"ssh_keys",
 "74"=>"sshd",
 "1000"=>"guest",
 "48"=>"apache"}
++++++++++++++++++++++++++++++++++++++++++++++++++
create output directory - 
/share/build/etc/puppet
/share/build/etc/puppet/hieradata
/share/build/etc/puppet/manifests
/share/build/etc/puppet/modules
++++++++++++++++++++++++++++++++++++++++++++++++++
create files - 
/share/build/etc/puppet/autosign.conf
*
/share/build/etc/puppet/hiera.yaml
---
:backends:
  - yaml
:yaml:
  :datadir: /etc/puppet/hieradata
:hierarchy:
  - "%{::hostname}"
  - default
/share/build/etc/puppet/manifests/site.pp
node default {
  Group <| |> -> User <| |>
  User <| |> -> Package <| |>
  Package <| |> -> File <| |>
  File <| |> -> Service <| |>
  
  hiera_include("classes")
}
++++++++++++++++++++++++++++++++++++++++++++++++++
create modules - 
---base::account
/share/build/etc/puppet/modules/base/manifests/account.pp
class base::account (
) {

  group { 'guest':
    ensure => 'present',
    gid    => '1000',
  }

  user { 'guest':
    ensure           => 'present',
    gid              => '1000',
    home             => '/home/guest',
    password         => '$6$YtdVuKy6$qoKZLThvlBfSwc8hDj2sWAMx9/CM4Sss61nqOdjV9Zp2iI4QKD5jQgBuX5cKhflQFoRizNDh95nl55e8sqhAN1',
    shell            => '/bin/bash',
    uid              => '1000',
  }

  file { '/home/guest':
    ensure => 'directory',
    group  => 'guest',
    mode   => '700',
    owner  => 'guest',
  }

}

---base::directory
/share/build/etc/puppet/modules/base/manifests/directory.pp
class base::directory (
) {

  file { '/home/guest/tool':
    ensure => 'directory',
    group  => 'guest',
    mode   => '775',
    owner  => 'guest',
  }

  file { '/home/guest/link':
    ensure => 'link',
    group  => 'guest',
    mode   => '777',
    owner  => 'guest',
    target => 'tool',
  }

}

---apache::install
/share/build/etc/puppet/modules/apache/manifests/install.pp
class apache::install (
  $httpd_ensure,
) {

  package { 'httpd':
    ensure => $httpd_ensure,
  }

}

---apache::config_%{::hostname}
/share/build/etc/puppet/modules/apache/manifests/config_web01.pp
copy : /etc/httpd/conf/httpd.conf
  => : /share/build/etc/puppet/modules/apache/templates/web01/httpd.conf.erb
copy : /etc/httpd/conf.d/prefork.conf
  => : /share/build/etc/puppet/modules/apache/templates/default/prefork.conf.erb
copy : /etc/httpd/modules/mod_cgi.so
  => : /share/build/etc/puppet/modules/apache/files/modules/mod_cgi.so
copy : /tmp/prefork.conf
  => : /share/build/etc/puppet/modules/apache/templates/tmp/prefork.conf.erb
copy : /tmp/mod_cgi.so
  => : /share/build/etc/puppet/modules/apache/files/tmp/mod_cgi.so
class apache::config_web01 (
  $httpd_conf_tmpl,
  $prefork_conf_tmpl,
  $mod_cgi_so_src,
  $tmp_prefork_conf_tmpl,
  $tmp_mod_cgi_so_src,
) {

  file { '/etc/httpd/conf/httpd.conf':
    ensure  => 'file',
    content => template($httpd_conf_tmpl),
    group   => 'root',
    mode    => '644',
    owner   => 'root',
  }

  file { '/etc/httpd/conf.d/prefork.conf':
    ensure  => 'file',
    content => template($prefork_conf_tmpl),
    group   => 'root',
    mode    => '644',
    owner   => 'root',
  }

  file { '/etc/httpd/modules/mod_cgi.so':
    ensure  => 'file',
    source  => "puppet:///modules/${mod_cgi_so_src}",
    group   => 'root',
    mode    => '755',
    owner   => 'root',
  }

  file { '/tmp/prefork.conf':
    ensure  => 'file',
    content => template($tmp_prefork_conf_tmpl),
    group   => 'root',
    mode    => '644',
    owner   => 'root',
  }

  file { '/tmp/mod_cgi.so':
    ensure  => 'file',
    source  => "puppet:///modules/${tmp_mod_cgi_so_src}",
    group   => 'root',
    mode    => '755',
    owner   => 'root',
  }

}

---apache::service
/share/build/etc/puppet/modules/apache/manifests/service.pp
class apache::service (
  $httpd_ensure,
  $httpd_enable,
) {

  service { 'httpd':
    ensure => $httpd_ensure,
    enable => $httpd_enable,
  }

}

++++++++++++++++++++++++++++++++++++++++++++++++++
create hieradata - 
/share/build/etc/puppet/hieradata/web01.yaml
---
classes:
- base::account
- base::directory
- apache::install
- apache::config_web01
- apache::service
apache::install::httpd_ensure: 2.4.6-31.el7.centos.1
apache::config_web01::httpd_conf_tmpl: apache/%{::hostname}/httpd.conf.erb
apache::config_web01::prefork_conf_tmpl: apache/default/prefork.conf.erb
apache::config_web01::mod_cgi_so_src: apache/modules/mod_cgi.so
apache::config_web01::tmp_prefork_conf_tmpl: apache/tmp/prefork.conf.erb
apache::config_web01::tmp_mod_cgi_so_src: apache/tmp/mod_cgi.so
apache::service::httpd_ensure: running
apache::service::httpd_enable: 'true'
```

## 結果のディレクトリツリー

```
[root@web01 share]# tree build
build
└── etc
    └── puppet
        ├── autosign.conf
        ├── hieradata
        │   └── web01.yaml
        ├── hiera.yaml
        ├── manifests
        │   └── site.pp
        └── modules
            ├── apache
            │   ├── files
            │   │   ├── modules
            │   │   │   └── mod_cgi.so
            │   │   └── tmp
            │   │       └── mod_cgi.so
            │   ├── manifests
            │   │   ├── config_web01.pp
            │   │   ├── install.pp
            │   │   └── service.pp
            │   └── templates
            │       ├── default
            │       │   └── prefork.conf.erb
            │       ├── tmp
            │       │   └── prefork.conf.erb
            │       └── web01
            │           └── httpd.conf.erb
            └── base
                └── manifests
                    ├── account.pp
                    └── directory.pp

16 directories, 14 files
```
