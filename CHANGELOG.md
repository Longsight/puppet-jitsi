# Changelog

All notable changes to this project will be documented in this file.

## Release 0.2.0

**Added**

* Override for the service file to disable logging stdout to file (that's what journald is for).
* Explicity set `JVB_HOST` to localhost for new service file.

**Removed**

* Remove custom systemd script; rely on vendor script, which exists now.

## Release 0.1.0

Gotta start somewhere.
