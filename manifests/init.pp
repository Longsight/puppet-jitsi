## vim: set ts=2 sw=2 sts=0 et foldmethod=marker:
## copyright: B1 Systems GmbH <info@b1-systems.de>, 2018
## license: GPLv3+, http://www.gnu.org/licenses/gpl-3.0.html
## author: Tobias Wolter <tobias.wolter@b1-systems.de>, 2018
# @summary Configures a Jitsi Meet instance.
# @author Tobias Wolter <tobias.wolter@b1-systems.de>
# @param release Which release (stable, testing, nightly) to use (default: stable)
# @param manage_repo If the repository should be managed by this module. (default: true)
# @param packages Either 'all' or a list of jitsi packages to install. (default: 'all')
#   Valid choices: +jitsi-videobridge+, +jicofo+, +jigasi+
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
  Enum[
    'stable',
    'testing',
    'nightly'
  ] $release,
  Variant[
    Enum['all'],
    Array[
      Enum[
        'jitsi-videobridge',
        'jicofo',
        'jigasi'
      ]
    ]
  ] $packages,
  Struct[{
    cert => Stdlib::Unixpath,
    key  => Stdlib::Unixpath,
  }] $ssl,
  #lint:endignore:trailing_comma
) {
  # Repository management{{{
  if $manage_repo {
    class { 'jitsi::repo':
      release => $release,
    }
  }
  # }}}
  # Install packages{{{
  $package_list = $packages ? {
    String => [ 'jitsi-meet' ],
    Array  => $packages,
  }
  ensure_packages([
    'npm',
    'nodejs',
  ] + $package_list, {
    ensure => present,
  })
  # }}}
  # Configure SSL certificate for jetty{{{
  java_ks { "${hostname}:/etc/jitsi/videobridge/${hostname}.jks":
    ensure      => latest,
    certificate => $ssl['cert'],
    private_key => $ssl['key'],
    password    => fqdn_rand_string(32, '', 'videobridge-keystore'),
  }
  # }}}
  # Configure prosody{{{
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

  class { 'prosody':
    custom_options => {
      https_ssl            => {
        ssl_cert => $ssl['cert'],
        ssl_key  => $ssl['key'],
      },
      consider_bosh_secure => true,
    },
  }

  prosody::virtualhost { $hostname:
    ensure         => present,
    ssl_cert       => $ssl['cert'],
    ssl_key        => $ssl['key'],
    custom_options => {
      modules_enabled => [
        'bosh',
        'pubsub',
        'ping',
      ],
    },
  }
  # }}}
}
