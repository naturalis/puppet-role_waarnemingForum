# == Class: role_waarnemingforum
#
# This role creates the necessary configuration for the forum.waarneming.nl webservice.
#
class role_waarnemingforum (
  $mysql_root_password = undef,
  $mysql_override_options = {
  },
  $system_user = 'forum',
  $web_root = "/home/${system_user}/www",
  $server_name = ['forum.waarneming.nl'],
  $dbuser = undef,
  $dbpass = undef,
  $dbname = 'forum',
  $dbpref = 'smf_',
  $dbhost = 'localhost',
  $smf_version = '2.0.14',
  $smf_maintenance = 0,
  $smf_cookie = undef,
  $smf_mailfrom = undex,
  $smf_image_proxy_secret = undef,
) {
  # Install database
  class { '::mysql::server':
    root_password =>  $mysql_root_password,
    remove_default_accounts =>  true,
    override_options =>  $mysql_override_options,
  }

  # Create database, db user and grant permissions
  mysql::db { $dbname:
    user     => $dbuser,
    password => $dbpass,
    host     => $dbhost,
    grant    => ['ALL'],
  }

  # Create forum user
  user { $system_user:
    ensure     => present,
    managehome => true,
  }

  # Create forum dir
  file { [ $web_root, "${web_root}/smf" ]:
    ensure  => directory,
    owner   => $system_user,
    group   => $system_user,
  }

  # Install PHP with FPM
  class { '::php':
    ensure     => present,
    fpm        => true,
    extensions => {
      mysql  => {},
      mcrypt => {},
    },
    fpm_pools  => {
      www    => {
        ensure => absent,
      },
      forum => {
        listen      => '/run/php/php7.0-fpm.sock',
        listen_mode => '0666',
        user        => $system_user,
        group       => $system_user,
      },
    },
  }

  # Install memcached for caching and user sessions
  class { 'memcached': }

  # Install webserver
  class { 'nginx':
    keepalive_timeout => '60',
  }

  # Configure VHOST
  nginx::resource::server { 'forum':
    ensure               => present,
    server_name          => $server_name,
    use_default_location => false,
    www_root             => $web_root,
    server_cfg_prepend   => {
      server_name_in_redirect => 'off',
    },
    locations            => {
      forum_root => {
        location            => ' = /',
        www_root            => '~',
        index_file          => [],
        location_custom_cfg => {
          return => '301 /smf/',
        },
      },
      forum_fpm  => {
        location      => '~ \.php$',
        fastcgi       => 'unix:/var/run/php/php7.0-fpm.sock',
        fastcgi_index => 'index.php',
        www_root      => undef,
        index_files   => undef,
      },
    }
  }

  # Download and unpack SMF
  $smf_version_dashed = regsubst($smf_version,'\.', '-', 'G')

  archive { "/tmp/smf_${smf_version_dashed}_install.tar.gz":
    ensure        => present,
    extract       => true,
    extract_path  => "${web_root}/smf",
    source        => "https://download.simplemachines.org/index.php/smf_${smf_version_dashed}_install.tar.gz",
    creates       => "${web_root}/smf/index.php",
    cleanup       => true,
    user          => $system_user,
    group         => $system_user,
    require       => File["${web_root}/smf"],
  }

  # Remove installation php script
  file { "${web_root}/smf/install.php":
    ensure  => absent,
    require => Archive["/tmp/smf_${smf_version_dashed}_install.tar.gz"],
  }

  # Create SMF configuration
  file { "${web_root}/smf/Settings.php":
    content => template('role_waarnemingforum/Settings.php.erb'),
    owner   => $system_user,
    group   => $system_user,
    mode    => '0640',
  }
}
