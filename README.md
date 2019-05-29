# jitsi

## Table of Contents

1. [Description](#description)
2. [Usage - Configuration options and additional functionality](#usage)
3. [Reference](#reference)
3. [Limitations - OS compatibility, etc.](#limitations)

## Description

This module rolls out a (working) Jitsi Meet installation with jvb and jicofo.

## Usage

Basic usage is simply including the class, defining the host name and SSL certificates to use:

```
class { 'jitsi':
  hostname => $facts['fqdn'],
  ssl      => {
    certificate => "/etc/ssl/${facts['fqdn']/fullchain.pem",
    key         => "/etc/ssl/${facts['fqdn']/privkey.pem",
  },
}
```

## Reference

See [REFERENCE.md](REFERENCE.md).

## Limitations

Operating system compatibility is defined in [metadata.json](metadata.json).
