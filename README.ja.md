[English](README.md)

# puppet-manifest-maker

これは構築済みのサーバから設定を取得し、Puppetマニフェストを作成するRubyスクリプトです。
設定取得は、対象リソースをYAML形式で定義したファイルを元に行います。

サーバの設定ファイルの回収もできるため、**サーバ設定をスナップショット的にPuppetマニフェストにすることを目的としています。**
実行したサーバのマニフェストを作成するローカル実行と、SSH接続先のサーバのマニフェストを作成するリモート実行ができます。

設定を取得するサーバには、事前にpuppetのインストールが必要です。
また、リモート実行を行う場合、スクリプト実行側にnet-ssh, net-scpのインストールも必要です。
動作確認をCentOS上で行っているため、Red Hat系のLinux以外ではうまく動かいない場合があります。

## インストール方法

### puppet-manifest-makerのインストール
任意のディレクトリにgit cloneを行うか、[Download ZIP](https://github.com/kijibato/puppet-manifest-maker/archive/master.zip)したリポジトリを解凍してください。

git clone
```
$ git clone https://github.com/kijibato/puppet-manifest-maker.git
```

### net-sshとnet-scpのインストール
リモート実行する場合、net-ssh, net-scpを利用するため、下記コマンドでインストールを行ってください。

```
$ gem install net-ssh
$ gem install net-scp
```

## 基本的な使い方
いまのところコマンド実行は、スクリプトを配置しているディレクトリが推奨です。

### ローカル実行
実行は下記コマンドです。

```
$ ruby manifest_maker.rb -f INPUT_FILE
```

生成されたマニフェストは、recieve/localhostに出力されます。


### リモート実行
実行は下記コマンドです。
リモート実行はSSH接続で行うため、事前に後述のSSHの[設定変更](#configuration)が必要です。

```
$ ruby manifest_maker.rb -H host1,host2 -f INPUT_FILE
```

生成されたマニフェストは、recieve/hostnameに出力されます。

### オプション

-H HOSTS, --hosts=HOSTS

    対象ホストをコンマで区切った文字列

-f INPUT_FILE, --file=INPUT_FILE

    取得するリソースを定義したファイル

## リソース定義ファイル

### リソース定義ファイル概要

実行時に指定するリソース定義ファイルは、YAML形式で対象リソースを下記のルールで記載してください。

```
---
クラス名:
  リソースタイプ:
    - "リソースタイトル"
```

クラス名は::で区切られたもので、::が１つの場合（例、hoge::fuga）のみ対応しています。
現時点で対応しているResource Typeは、

- user
- group
- file
- package
- service
- yumrepo

です。

### fileリソース
fileリソースで対象ファイルを回収する場合、設定ファイルはtemplate、バイナリファイルはsourceの指定が必要です。

```
apache::config:
  file:
    - "/etc/httpd/conf/httpd.conf": template
    - "/etc/httpd/modules/mod_cgi.so": source
```

template,sourceのファイルの格納先も設定できます。格納先パスはPuppetのtemplateのパス記載に従います。生成後のマニフェストを再利用しやすいよう、格納先を設定する方がよいかと思います。

```
apache::config:
  file:
    - "/etc/httpd/conf/httpd.conf": template="apache/web01/httpd.conf.erb"
    - "/etc/httpd/modules/mod_cgi.so": source="apache/modules/mod_cgi.so"
```

なお、sourceについては、下記URIのpuppet:///modules/以降を指定してください。

```
puppet:///modules/<MODULE NAME>/<FILE PATH>
```

### facterの利用
サーバごとにクラス名やファイルの格納パスを変えたい場合は、facterが利用できます。
%{::facter変数}の部分をfacterの結果に置き換えます。

```
apache::config_%{::hostname}:
  file:
    - "/etc/httpd/conf/httpd.conf": template="apache/%{::hostname}/httpd.conf.erb"
```

なお、デフォルト設定では、下記項目だけ利用可能ですが、後述の[設定変更](#configuration)によって他の項目も利用できるようになります。
（※意図しないfacter結果でバグるのを防ぐ目的で制限しているため、変更は非推奨です。）

- osfamily
- operatingsystem
- operatingsystemmajrelease
- operatingsystemrelease
- hostname
- architecture

### リソース定義ファイルサンプル

``` sample/sample_input.yaml
---
base::account:
  group:
    - "guest"
  user:
    - "guest"
  file:
    - "/home/guest"
base::directory:
  file:
    - "/home/guest/tool"
    - "/home/guest/link"
base::yumrepo:
  yumrepo:
    - "epel"
    - "epel-debuginfo"
    - "epel-source"
apache::install:
  package:
    - "httpd"
apache::config_%{::hostname}:
  file:
    - "/etc/httpd/conf/httpd.conf": template="apache/%{::hostname}/httpd.conf.erb"
#    - "/etc/httpd/conf/httpd.conf": template="apache/web01/httpd.conf.erb"
    - "/etc/httpd/conf.d/prefork.conf": template='apache/default/prefork.conf.erb'
    - "/etc/httpd/modules/mod_cgi.so": source=apache/modules/mod_cgi.so
    - "/tmp/prefork.conf": template
    - "/tmp/mod_cgi.so": source
apache::service:
  service:
    - "httpd"
```

## <a id="configuration">設定変更</a>




## 以降まだ記載が古いです

## 実行例

### 確認環境

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

### 実行ログ例

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

## 生成マニフェストの構成例

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
