[English](README.md)

# puppet-manifest-maker

これは構築済みのサーバから設定を取得し、Puppetのマニフェストを作成するRubyスクリプトです。
**サーバの設定を、スナップショットをとるようにマニフェストにすることを目的としています。**

- 対象リソースを列挙したファイルを元に、設定を取得しマニフェストの作成ができます。
- fileリソースでは、サーバの設定ファイルの回収もできます。
- 実行したサーバのマニフェストを作成するローカル実行と、SSH接続先のサーバのマニフェストを作成するリモート実行ができます。

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

また、net-ssh接続時に、パスワードが異なっていた場合に、パスワード再入力ができますが、highlineがインストールされていないと入力がマスクされないようです。その場合、次のようなエラー文が表示されます。

```
Text will be echoed in the clear. Please install the HighLine or Termios libraries to suppress echoed text.
```

パスワードを正しく設定していれば問題ないはずですが、再入力時に隠したい場合は下記コマンドでhighlineをインストールしてください。

```
$ gem install highline
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

実行時に指定するリソース定義ファイルはYAML形式です。
対象リソースを下記のルールで記載してください。

```
---
クラス名:
  リソースタイプ:
    - "リソースタイトル"
```

クラス名は、::区切りが１つの場合（例、hoge::fuga）のみ対応しています。
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

### 設定変更概要

スクリプトの設定は、conf/default.yamlとconf/customize.yamlで行います。
default.yamlの設定を、customize.yamlの設定で上書くようになっています。
default.yamlの設定を変更したい場合、同じディレクトリにcustomize.yamlをコピー後、customize.yamlを変更してください。

### puppet, facterコマンドのパス変更

puppet,facterのコマンドのパスがpuppet,facterではない環境では、次の箇所を適切なパスに変更してください。

変更前

```
puppet:
  path: 'puppet'
facter:
  path: 'facter'
```

変更例

```
puppet:
  path: '/opt/puppetlabs/bin/puppet'
facter:
  path: '/opt/puppetlabs/bin/facter'
```

パス設定に誤りがある場合、次のようなエラーがでます。

```
#<RuntimeError: puppet: No such command on hostname>
or
#<RuntimeError: facter: No such command on hostname>
```

### SSH設定変更

SSH接続は、net-sshのSSH接続メソッドNet::SSH.startにuser, optionsを使って接続するようになっています。userは、puppet, facter, ファイルコピー(cp, scp)を行うため、rootユーザ推奨です。optionsについては、[net-sshのドキュメント](http://net-ssh.github.io/net-ssh/)を参照してください。Method Indexの::startメソッドに使えるオプションの記載があります。

#### 例１：パスワード接続
:passwordを適切なパスワードに変更してください。

```
ssh:
  user: 'root'
  options:
    :password: 'yourpassword'
```

#### 例２：公開鍵認証方式（パスフレーズなし）
秘密鍵を/root/.ssh/id_rsaに配置している場合です。

```
ssh:
  user: 'root'
  options:
    :keys:
      - '/root/.ssh/id_rsa'
```

#### 例３：公開鍵認証方式（パスフレーズあり）
秘密鍵を/root/.ssh/id_rsaに配置している場合です。
:passphraseは適切なパスフレーズに変更してください。

```
ssh:
  user: 'root'
  options:
    :keys:
      - '/root/.ssh/id_rsa'
    :passphrase: 'yourpassphrase'
```

### その他設定
その他設定でdefault.yamlに記載されている項目の説明です。
シンタックスは、YAML形式です。

```
---
resource:                     # リソースタイプ
  group:                      # groupリソース
    attributes:               # 属性
      reject: []              # マニフェストに含まない属性、[]は制限なし
  user:                       # userリソース
    attributes:               # 属性
      reject:                 # マニフェストに含まない属性
        - 'password_max_age'  # password_max_ageは含まない
        - 'password_min_age'  # password_min_ageは含まない
  package:                    # packageリソース
    attributes:               # 属性
      reject: []              # マニフェストに含まない属性、[]は制限なし
    param_ensure: true        # クラス生成時に、ensure属性を引数にする(true/false)
  file:                       # fileリソース
    attributes:               # 属性
      reject:                 # マニフェストに含まない属性
        - 'ctime'             # ctimeは含まない
        - 'mtime'             # mtimeは含まない
        - 'type'              # typeは含まない
    user_name: true           # uidをユーザ名で表示する(true/false)
    group_name: true          # gidをグループ名で表示する(true/false)
    param_template: true      # クラス生成時に、content属性のtemplateを引数にする(true/false)
    param_source: true        # クラス生成時に、source属性を引数にする(true/false)
  service:                    # serviceリソース
    attributes:               # 属性
      reject: []              # マニフェストに含まない属性、[]は制限なし
    param_ensure: true        # クラス生成時に、ensure属性を引数にする(true/false)
    param_enable: true        # クラス生成時に、enable属性を引数にする(true/false)
  yumrepo:                    # yumrepoリソース
    attributes:               # 属性
      reject: []              # マニフェストに含まない属性、[]は制限なし
    param_ensure: true        # クラス生成時に、ensure属性を引数にする(true/false)
    param_enabled: true       # クラス生成時に、enabled属性を引数にする(true/false)
puppet:                       # puppet
  path: 'puppet'              # puppetパス
facter:                       # facter
  path: 'facter'              # facterパス
  allow:                      # facter置換で許可するもの
    - 'osfamily'
    - 'operatingsystem'
    - 'operatingsystemmajrelease'
    - 'operatingsystemrelease'
    - 'hostname'
    - 'architecture'
verbose: true                 # 実行ログを詳細にする(true/false)
ssh:                          # SSH設定(詳細は上記)
  user: 'root'                # SSHログインユーザ
  options:                    # SSHオプション
    :password: 'yourpassword' # SSHログインパスワード
```

## 実行例
実行例です。

### 確認環境

```
[root@web01 puppet-manifest-maker]# uname -n    
web01
[root@web01 puppet-manifest-maker]# cat /etc/centos-release
CentOS Linux release 7.1.1503 (Core) 
[root@web01 puppet-manifest-maker]# ruby --version
ruby 2.0.0p598 (2014-11-13) [x86_64-linux]
[root@web01 puppet-manifest-maker]# puppet --version
3.8.4
[root@web01 puppet-manifest-maker]# facter --version
2.4.4
```

### 例)実行ログ

```
[root@web01 puppet-manifest-maker]# ruby manifest_maker.rb -f sample_input.yaml              
++++++++++++++++++++++++++++++++++++++++++++++++++
 localhost
++++++++++++++++++++++++++++++++++++++++++++++++++
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
--------------------------------------------------
create output directory - 
/root/puppet-manifest-maker/receive/localhost
/root/puppet-manifest-maker/receive/localhost/hieradata
/root/puppet-manifest-maker/receive/localhost/manifests
/root/puppet-manifest-maker/receive/localhost/modules
--------------------------------------------------
create files - 
/root/puppet-manifest-maker/receive/localhost/autosign.conf
*
/root/puppet-manifest-maker/receive/localhost/hiera.yaml
---
:backends:
  - yaml
:yaml:
  :datadir: /etc/puppet/hieradata
:hierarchy:
  - "%{::hostname}"
  - default
/root/puppet-manifest-maker/receive/localhost/manifests/site.pp
node default {
  Group <| |> -> User <| |>
  User <| |> -> Yumrepo <| |>
  Yumrepo <| |> -> Package <| |>
  Package <| |> -> File <| |>
  File <| |> -> Service <| |>
  
  hiera_include("classes")
}
--------------------------------------------------
create modules - 
---base::account
/root/puppet-manifest-maker/receive/localhost/modules/base/manifests/account.pp
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
/root/puppet-manifest-maker/receive/localhost/modules/base/manifests/directory.pp
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

---base::yumrepo
/root/puppet-manifest-maker/receive/localhost/modules/base/manifests/yumrepo.pp
class base::yumrepo (
  $epel_ensure,
  $epel_enabled,
  $epel_debuginfo_ensure,
  $epel_debuginfo_enabled,
  $epel_source_ensure,
  $epel_source_enabled,
) {

  yumrepo { 'epel':
    ensure         => $epel_ensure,
    descr          => 'Extra Packages for Enterprise Linux 7 - $basearch',
    enabled        => $epel_enabled,
    failovermethod => 'priority',
    gpgcheck       => '1',
    gpgkey         => 'file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7',
    mirrorlist     => 'https://mirrors.fedoraproject.org/metalink?repo=epel-7&arch=$basearch',
  }

  yumrepo { 'epel-debuginfo':
    ensure         => $epel_debuginfo_ensure,
    descr          => 'Extra Packages for Enterprise Linux 7 - $basearch - Debug',
    enabled        => $epel_debuginfo_enabled,
    failovermethod => 'priority',
    gpgcheck       => '1',
    gpgkey         => 'file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7',
    mirrorlist     => 'https://mirrors.fedoraproject.org/metalink?repo=epel-debug-7&arch=$basearch',
  }

  yumrepo { 'epel-source':
    ensure         => $epel_source_ensure,
    descr          => 'Extra Packages for Enterprise Linux 7 - $basearch - Source',
    enabled        => $epel_source_enabled,
    failovermethod => 'priority',
    gpgcheck       => '1',
    gpgkey         => 'file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7',
    mirrorlist     => 'https://mirrors.fedoraproject.org/metalink?repo=epel-source-7&arch=$basearch',
  }

}

---apache::install
/root/puppet-manifest-maker/receive/localhost/modules/apache/manifests/install.pp
class apache::install (
  $httpd_ensure,
) {

  package { 'httpd':
    ensure => $httpd_ensure,
  }

}

---apache::config_%{::hostname}
/root/puppet-manifest-maker/receive/localhost/modules/apache/manifests/config_web01.pp
copy : /etc/httpd/conf/httpd.conf
  => : /root/puppet-manifest-maker/receive/localhost/modules/apache/templates/web01/httpd.conf.erb
copy : /etc/httpd/conf.d/prefork.conf
  => : /root/puppet-manifest-maker/receive/localhost/modules/apache/templates/default/prefork.conf.erb
copy : /etc/httpd/modules/mod_cgi.so
  => : /root/puppet-manifest-maker/receive/localhost/modules/apache/files/modules/mod_cgi.so
copy : /tmp/prefork.conf
  => : /root/puppet-manifest-maker/receive/localhost/modules/apache/templates/tmp/prefork.conf.erb
copy : /tmp/mod_cgi.so
  => : /root/puppet-manifest-maker/receive/localhost/modules/apache/files/tmp/mod_cgi.so
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
/root/puppet-manifest-maker/receive/localhost/modules/apache/manifests/service.pp
class apache::service (
  $httpd_ensure,
  $httpd_enable,
) {

  service { 'httpd':
    ensure => $httpd_ensure,
    enable => $httpd_enable,
  }

}

--------------------------------------------------
create hieradata - 
/root/puppet-manifest-maker/receive/localhost/hieradata/web01.yaml
---
classes:
- base::account
- base::directory
- base::yumrepo
- apache::install
- apache::config_web01
- apache::service
base::yumrepo::epel_ensure: present
base::yumrepo::epel_enabled: '1'
base::yumrepo::epel_debuginfo_ensure: present
base::yumrepo::epel_debuginfo_enabled: '0'
base::yumrepo::epel_source_ensure: present
base::yumrepo::epel_source_enabled: '0'
apache::install::httpd_ensure: 2.4.6-40.el7.centos
apache::config_web01::httpd_conf_tmpl: apache/%{::hostname}/httpd.conf.erb
apache::config_web01::prefork_conf_tmpl: apache/default/prefork.conf.erb
apache::config_web01::mod_cgi_so_src: apache/modules/mod_cgi.so
apache::config_web01::tmp_prefork_conf_tmpl: apache/tmp/prefork.conf.erb
apache::config_web01::tmp_mod_cgi_so_src: apache/tmp/mod_cgi.so
apache::service::httpd_ensure: running
apache::service::httpd_enable: 'true'
```

## 例)作成されたマニフェストの構成

```
[root@web01 puppet-manifest-maker]# tree receive 
receive
└── localhost
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
                ├── directory.pp
                └── yumrepo.pp

15 directories, 15 files
```
