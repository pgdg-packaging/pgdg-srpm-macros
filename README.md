# pgdg-srpm-macros

RPM macros used by the [PostgreSQL DNF repository](https://yum.postgresql.org/) / [PostgreSQL ZYPP repository](https://zypp.postgresql.org/)  and when building SRPM and binary packages for PostgreSQL and related software across supported distributions.

## Overview

`pgdg-srpm-macros` provides a set of RPM macros that standardise build-time paths, version identifiers, and other packaging conventions across the PGDG RPM ecosystem. It is a build-time dependency for some of the PGDG spec files and should be installed on any system used to build PGDG packages from source.

## Contents

| File | Description |
|---|---|
| `macros.pgdg-postgresql` | RPM macro definitions for PGDG packaging |

## Installation

The package is available from the PGDG repository. On RHEL/Fedora-based systems:

```bash
dnf install pgdg-srpm-macros
```

On SUSE systems:

```bash
zypper install pgdg-srpm-macros
```

Or install directly from an SRPM/RPM built from this repository.

## Usage

Once installed, the macros are automatically available to `rpmbuild` and `mock`. Spec files in the PGDG ecosystem use these macros to ensure consistent directory layouts and versioning across all supported distributions (RHEL, Fedora, SLES, etc.).

## License

PostgreSQL — see [LICENSE.txt](LICENSE.txt) for details.

## Maintainer

Devrim Gündüz &lt;devrim@gunduz.org&gt;
