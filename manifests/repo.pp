## vim: set ts=2 sw=2 sts=0 et foldmethod=marker:
## copyright: B1 Systems GmbH <info@b1-systems.de>, 2018
## license: GPLv3+, http://www.gnu.org/licenses/gpl-3.0.html
## author: Tobias Wolter <tobias.wolter@b1-systems.de>, 2018

# Configures the official binary package repository for Jitsi Meet
# @summary Configure binary package repository for Jitsi Meet
# @author Tobias Wolter <tobias.wolter@b1-systems.de>
# @param fingerprint Fingerprint of the repository key
# @param release Which release to use. (+stable+, +testing+, +nightly+)
class jitsi::repo (
  Stdlib::Base64 $fingerprint,
  Jitsi::Release $release,
) {
  case $facts['os']['family'] {
    'Debian': {
      include apt
      apt::key { 'jitsi-meet':
        id     => $fingerprint,
        source => 'https://download.jitsi.org/jitsi-key.gpg.key',
      }

      apt::source { 'jitsi-meet':
        location => 'https://download.jitsi.org/',
        release  => "${release}/",
        repos    => '',
      }
    }
    default: {
      fail("Operating system family ${facts['os']['family']} not supported")
    }
  }
}
