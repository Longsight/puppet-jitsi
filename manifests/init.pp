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
# @param packages Either 'all' or a list of jitsi packages to install. (default: 'all')
#   Valid choices: +jitsi-videobridge+, +jicofo+, +jigasi+
# @param release Which release (stable, testing, nightly) to use (default: stable)
# @param secrets Secrets to define for the components. Will default to a string based on the host name.
#   Possible keys: +component+, +focus+, +video+
# @param ssl Location to SSL +certificate+ and +key+. No default.
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
  # Authentifcation configuration{{{
  case $authentication {
    'ldap': {
      assert_type(Struct[{
        # TODO formulate data types
        # TODO check for completeness, this was just taken from a test install
        ldap_base     => String[1],
        ldap_server   => String[1],
        ldap_rootdn   => String[1],
        ldap_password => String[1],
        ldap_tls      => Boolean,
        ldap_filter   => String[1],
      }], $authentication_options)
      $auth_configuration = {
        authentication => 'ldap',
      } + $authentication_options
    }
    default: {
      fail("Authentication method ${authentication} not implemented yet, sorry.")
    }
  }
  # }}}
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
    custom_options => {
      consider_bosh_secure => true,
      # https_ssl            => {
      #   ssl_cert => $ssl['certificate'],
      #   ssl_key  => $ssl['key'],
      # },
    },
  }
  # Vhosts{{{
  $vhost_modules = [
    'bosh',
    'pubsub',
    'ping',
  ]
  # General vhost for jitsi meet{{{
  prosody::virtualhost { $hostname:
    ensure         => present,
    ssl_cert       => $ssl['certificate'],
    ssl_key        => $ssl['key'],
    custom_options => {
      modules_enabled => $vhost_modules,
    },
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
      include nginx
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

    default: {
      fail('That webserver is not supported yet.')
    }
  }
  #}}}
  # Jitsi{{{
  # Meet{{{
  file { '/etc/jitsi/meet':
    ensure => directory,
  }

  file { "/etc/jitsi/meet/${hostname}-config.js":
    ensure  => file,
    content => template('jitsi/config.js.erb'),
    require => Package['jitsi-meet-web'],
  }
  # }}}
  # Jicofo{{{
  file { '/etc/jitsi/jicofo/config':
    ensure  => file,
    content => template('jitsi/jicofo.erb'),
    require => Package['jicofo'],
  }
  # }}}
  # Videobridge{{{
  file { '/etc/jitsi/videobridge/config':
    ensure  => file,
    content => template('jitsi/videobridge.erb'),
  }
  # }}}
  # }}}
}
