## vim: set ts=2 sw=2 sts=0 et foldmethod=marker:
## copyright: B1 Systems GmbH <info@b1-systems.de>, 2018
## license: GPLv3+, http://www.gnu.org/licenses/gpl-3.0.html
## author: Tobias Wolter <tobias.wolter@b1-systems.de>, 2018

# @summary Configures a Jitsi Meet instance.
# @author Tobias Wolter <tobias.wolter@b1-systems.de>
# @param authentication What kind of authentication to use.
# @param authentication_options List of parameters to use for the authentication provider; provider-dependent.
# @param hostname Host name to use for the installation.
# @param manage_repo If the repository should be managed by this module. (default: true)
# @param manage_service Whether to manage certain services.
# @option manage_service [Boolean] :webserver
#      Manage the webserver service. Default: +true+
# @param packages Either 'all' or a list of jitsi packages to install. (default: 'all')
#   Valid choices: *jitsi-meet-web*, +jitsi-videobridge+, +jicofo+, +jigasi+
# @param release Which release (stable, testing, nightly) to use (default: stable)
# @param secrets Secrets to define for the components. Will default to a string based on the host name.
#   Possible keys: +component+, +focus+, +focus_user+ +video+
# @param ssl Location to SSL +certificate+ and +key+. No default.
# @param webserver Which web server to use for serving the content.
#     Currently supported: +nginx+.
# @param www_root Installation location of the jitsi meet files.
class jitsi (
  #lint:ignore:trailing_comma Readability confuses the linter; syntax error when used.
  Enum[
    'ldap',
    'local',
    'none'
  ] $authentication,
  Hash $authentication_options, # validated later
  Stdlib::Fqdn $hostname,
  Boolean $manage_repo,
  Struct[{
    'webserver' => Boolean,
  }] $manage_service,
  Variant[
    Enum['all'],
    Array[
      Enum[
        'jitsi-meet-web',
        'jitsi-videobridge',
        'jicofo',
        'jigasi'
      ]
    ]
  ] $packages,
  Jitsi::Release $release,
  Struct[{
    Optional[focus]      => String[1],
    Optional[focus-user] => String[1],
    Optional[video]      => String[1],
  }] $secrets,
  Struct[{
    certificate => Stdlib::Unixpath,
    key         => Stdlib::Unixpath,
  }] $ssl,
  Enum[
    'apache',
    'nginx',
    'none'
  ] $webserver,
  Stdlib::Unixpath $www_root,
  #lint:endignore:trailing_comma
) {
  include ::systemd::systemctl::daemon_reload

  # Variables{{{
  # We need to define some of the variables here to save en evaluation logic in the templates.
  $focus_secret      = pick($secrets['focus'], fqdn_rand_string(32, '', 'focus'))
  $focus_user_secret = pick($secrets['focus-user'], fqdn_rand_string(32, '', 'focus-user'))
  $video_secret      = pick($secrets['video'], fqdn_rand_string(32, '', 'video'))
  # }}}
  # Repository management{{{
  if $manage_repo {
    class { 'jitsi::repo':
      release => $release,
    }
  }
  # }}}
  # Install packages{{{
  $package_list = $packages ? {
    String => [ 'jitsi-meet-web', 'jitsi-videobridge', 'jicofo', 'jigasi' ],
    Array  => $packages,
  }
  ensure_packages([
    'npm',
    'nodejs',
  ] + $package_list, {
    ensure => present,
  })
  # }}}
  # Prosody{{{
  class { 'prosody':
    admins         => [
      "focus@auth.${hostname}",
    ],
    components     => {
      "conference.${hostname}"        => {
        type    => 'muc',
        options => {
          storage => 'null',
        },
      },
      "jitsi-videobridge.${hostname}" => {
        secret => $video_secret,
      },
      "focus.${hostname}"             => {
        secret => $focus_secret,
      },
    },
    modules        => [
      'groups',
      'smacks',
      'carbons',
      'mam',
      'lastactivity',
      'offline',
      'pubsub',
      'adhoc',
      'websocket',
      'http_altconnect',
      'muc',
    ],
    custom_options => {
      consider_bosh_secure      => true,
      consider_websocket_secure => true,
      cross_domain_bosh         => true,
      use_libevent              => true,
    },
  }
  # Vhosts{{{
  $vhost_modules = [
    'bosh',
    'pubsub',
    'ping',
  ]
  # General vhost for jitsi meet{{{
    case $authentication {
      'ldap': {
        assert_type(Struct[{
          base          => String[1],
          bind_dn       => String[1],
          bind_password => String[1],
          server        => String[1],
          tls           => Boolean,
          userfield     => String[1],
        }], $authentication_options)
        $custom_options = {
          authentication => 'ldap2',
          ldap           => {
            user          => {
              basedn        => $authentication_options['base'],
              usernamefield => $authentication_options['userfield'],
            },
            bind_dn       => $authentication_options['bind_dn'],
            bind_password => $authentication_options['bind_password'],
            hostname      => $authentication_options['server'],
            use_tls       => $authentication_options['tls'],
          },
        }
      }
      'local': {
        $custom_options = {
          authentication => 'internal_plain',
        }
      }
      'none', default: {
        $custom_options = {}
      }
    }

  prosody::virtualhost { $hostname:
    ensure         => present,
    ssl_cert       => $ssl['certificate'],
    ssl_key        => $ssl['key'],
    custom_options => {
      modules_enabled => $vhost_modules,
    } + $custom_options,
  }
  # }}}
    # Guest vhost{{{
    prosody::virtualhost { "guest.${hostname}":
      ensure         => present,
      ssl_cert       => $ssl['certificate'],
      ssl_key        => $ssl['key'],
      custom_options => {
        authentication         => 'anonymous',
        c2s_require_encryption => false,
        modules_enabled        => $vhost_modules,
      },
    }
    # }}}
    # Authentication vhost for conference focus user{{{
    prosody::virtualhost { "auth.${hostname}":
      ensure         => present,
      ssl_cert       => $ssl['certificate'],
      ssl_key        => $ssl['key'],
      custom_options => {
        authentication => 'internal_plain',
      },
    }
    # }}}
    # }}}
    # Create focus user{{{
    prosody::user { 'focus':
      pass => $focus_user_secret,
      host => "auth.${hostname}",
    }
    #}}}
  # }}}
  # Webserver{{{
  case $webserver {
    'nginx': {
      class { 'nginx':
        service_manage => $manage_service['webserver'],
      }
      nginx::resource::server { $hostname:
        index_files          => [ 'index.html' ],
        listen_port          => 443,
        ssl                  => true,
        ssl_cert             => $ssl['certificate'],
        ssl_key              => $ssl['key'],
        use_default_location => false,
        www_root             => $www_root,
      }

      Nginx::Resource::Location {
        server   => $hostname,
        ssl      => true,
        ssl_only => true,
        require  => Nginx::Resource::Server[$hostname],
      }

      nginx::resource::location { "${hostname} default":
        location            => '/',
        location_cfg_append => {
          ssi => 'on',
        },
      }

      nginx::resource::location { "${hostname} rewrite":
        location      => ' ~ ^/([a-zA-Z0-9=\?]+)$',
        rewrite_rules => [
          '^/(.*)$ / break',
        ],
      }

      nginx::resource::location { "${hostname} bosh":
        location         => '/http-bind',
        proxy            => 'http://localhost:5280/http-bind',
        proxy_set_header => [
          'X-Forwarded-For $remote_addr',
          'Host $http_host',
        ],
      }

      nginx::resource::location { "${hostname} xmpp websockets":
        location            => '/xmpp-websocket',
        proxy               => 'http://localhost:5280/xmpp-websocket',
        proxy_set_header    => [
          'Upgrade $http_upgrade',
          'Connection "upgrade"',
          'Host $host',
        ],
        proxy_http_version  => '1.1',
        location_cfg_append => {
          tcp_nodelay => 'on',
        },
      }
    }

    # default: {
    #   fail('That webserver is not supported yet.')
    # }
  }
  #}}}
  # Jitsi{{{
  # Meet{{{
  file { '/etc/jitsi/meet':
    ensure => directory,
  }

  file { "${www_root}/config.js":
    ensure  => file,
    content => template('jitsi/meet/config.js.erb'),
    require => Package['jitsi-meet-web'],
  }
  # }}}
  # Jicofo{{{
  file { '/etc/jitsi/jicofo/config':
    ensure  => file,
    content => template('jitsi/jicofo/config.erb'),
    require => Package['jicofo'],
  }
  # }}}
  # Videobridge{{{
  # Daemon configuration
  file { '/etc/jitsi/videobridge/config':
    ensure  => file,
    content => template('jitsi/videobridge/config.erb'),
  }

  # App configuration
  file { '/etc/jitsi/videobridge/sip-communicator.properties':
    ensure  => file,
    content => template('jitsi/videobridge/sip-communicator.properties.erb'),
  }

  # Remove old sysvinit script
  file { '/etc/init.d/jitsi-videobridge':
    ensure => absent,
    notify => Exec['refresh systemd'],
  }

  # Remove systemd script
  # The package now ships with one.
  file { '/etc/systemd/system/jvb.service':
    ensure => absent,
    notify => Exec['refresh systemd'],
  }

  file { '/etc/systemd/system/jitsi-videobridge.service.d':
    ensure => directory,
  }

  file { '/etc/systemd/system/jitsi-videobridge.service.d/no-logfile.conf':
    ensure  => present,
    content => "[Service]\nExecStart=\nExecStart=/usr/share/jitsi-videobridge/jvb.sh --host=\${JVB_HOST} --domain=\${JVB_HOSTNAME} --port=\${JVB_PORT} --secret=\${JVB_SECRET} \${JVB_OPTS}\n",
    notify  => Class['systemd::systemctl::daemon_reload'],
  }

  class { 'systemd::systemctl::daemon_reload':
    notify => [
      Service['prosody'],
      Service['jitsi-videobridge'],
      Service['jicofo'],
      Service['jigasi'],
    ]
  }

  # }}}
  # }}}
}
