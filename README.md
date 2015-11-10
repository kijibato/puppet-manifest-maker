# pusutools
puppet support tools

スクリプトを実行したサーバの設定を、Puppetマニフェストに変換するスクリプトです。
現時点では、user,group,file,package,serviceのみサポートしています。

## Sample

```
[root@web01 pusutools]# pwd
/share/pusutools
[root@web01 pusutools]# ls -l 
total 40
-rw-r--r-- 1 guest ftp 11358 Nov  5 13:34 LICENSE
-rw-r--r-- 1 guest ftp    33 Nov  5 13:34 README.md
-rw-r--r-- 1 guest ftp   566 Nov  2 18:00 config.yaml
-rw-r--r-- 1 guest ftp 16132 Nov  2 14:26 manifest_maker.rb
-rw-r--r-- 1 guest ftp   671 Nov  2 14:08 sample_input.yaml

[root@web01 pusutools]# ruby manifest_maker.rb --file sample_input.yaml
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
 "1000"=>"guest",
 "999"=>"ssh_keys",
 "48"=>"apache"}
++++++++++++++++++++++++++++++++++++++++++++++++++
create output directory - 
/share/pusutools/etc/puppet
/share/pusutools/etc/puppet/hieradata
/share/pusutools/etc/puppet/manifests
/share/pusutools/etc/puppet/modules
++++++++++++++++++++++++++++++++++++++++++++++++++
create files - 
/share/pusutools/etc/puppet/autosign.conf
*
/share/pusutools/etc/puppet/hiera.yaml
---
:backends:
  - yaml
:yaml:
  :datadir: /etc/puppet/hieradata
:hierarchy:
  - "%{::hostname}"
  - default
/share/pusutools/etc/puppet/manifests/site.pp
node default {
  hiera_include("classes")
}
++++++++++++++++++++++++++++++++++++++++++++++++++
create modules - 
---base::account
/share/pusutools/etc/puppet/modules/base/manifests/account.pp
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
/share/pusutools/etc/puppet/modules/base/manifests/directory.pp
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
/share/pusutools/etc/puppet/modules/apache/manifests/install.pp
class apache::install (
  $httpd_ensure,
) {

  package { 'httpd':
    ensure => $httpd_ensure,
  }

}

---apache::config_%{::hostname}
/share/pusutools/etc/puppet/modules/apache/manifests/config_web01.pp
copy : /etc/httpd/conf/httpd.conf
  => : /share/pusutools/etc/puppet/modules/apache/templates/web01/httpd.conf.erb
copy : /etc/httpd/conf.d/prefork.conf
  => : /share/pusutools/etc/puppet/modules/apache/templates/default/prefork.conf.erb
copy : /etc/httpd/modules/mod_cgi.so
  => : /share/pusutools/etc/puppet/modules/apache/files/modules/mod_cgi.so
copy : /tmp/prefork.conf
  => : /share/pusutools/etc/puppet/modules/apache/templates/tmp/prefork.conf
copy : /tmp/mod_cgi.so
  => : /share/pusutools/etc/puppet/modules/apache/files/tmp/mod_cgi.so
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
/share/pusutools/etc/puppet/modules/apache/manifests/service.pp
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
/share/pusutools/etc/puppet/hieradata/web01.yaml
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
apache::config_web01::tmp_prefork_conf_tmpl: apache/tmp/prefork.conf
apache::config_web01::tmp_mod_cgi_so_src: apache/tmp/mod_cgi.so
apache::service::httpd_ensure: running
apache::service::httpd_enable: 'true'
```

## output directory tree

```
[root@web01 pusutools]# tree etc/
etc/
`-- puppet
    |-- autosign.conf
    |-- hiera.yaml
    |-- hieradata
    |   `-- web01.yaml
    |-- manifests
    |   `-- site.pp
    `-- modules
        |-- apache
        |   |-- files
        |   |   |-- modules
        |   |   |   `-- mod_cgi.so
        |   |   `-- tmp
        |   |       `-- mod_cgi.so
        |   |-- manifests
        |   |   |-- config_web01.pp
        |   |   |-- install.pp
        |   |   `-- service.pp
        |   `-- templates
        |       |-- default
        |       |   `-- prefork.conf.erb
        |       |-- tmp
        |       |   `-- prefork.conf
        |       `-- web01
        |           `-- httpd.conf.erb
        `-- base
            `-- manifests
                |-- account.pp
                `-- directory.pp

15 directories, 14 files
```
