# pgdg-srpm-macros

RPM macros used by the [PostgreSQL DNF repository](https://yum.postgresql.org/) / [PostgreSQL ZYPP repository](https://zypp.postgresql.org/)  and when building SRPM and binary packages for PostgreSQL and related software across supported distributions.

## Overview

`pgdg-srpm-macros` provides a set of RPM macros that standardise build-time paths, version identifiers, and other packaging conventions across the PGDG RPM ecosystem. It is a build-time dependency for some of the PGDG spec files and should be installed on any system used to build PGDG packages from source.

## Contents

| File | Description |
|---|---|
| `macros.pgdg-postgresql` | RPM macro definitions for PGDG packaging |
| `pgdg-check-functions.sh` | Shell functions for running PostgreSQL test servers in `%check` |

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

## Install prefixes of the pgdg-* libraries

On RHEL, the libraries and tools that the GIS stack, pgBackRest and other
packages used to take from EPEL are built as `pgdg-<name>` packages,
installed under a versionless `/usr/pgdg-<name>` prefix:
`%{pgdg_hdf5instdir}` is `/usr/pgdg-hdf5`, for example. They do not install
an `ld.so.conf.d` file, and they do not provide their sonames, so they
never replace OS or EPEL libraries. Consumers require them by package name,
add the library directory of the prefix to their rpath, and filter the
sonames out of their automatic requirements:

```spec
%global __requires_exclude ^lib(hdf5[a-z_]*|aec|sz)\\.so
...
BuildRequires:	pgdg-srpm-macros >= 2.1.0 pgdg-hdf5-devel
Requires:	pgdg-hdf5%{?_isa}
...
export LDFLAGS="%{build_ldflags} -Wl,-rpath,%{pgdg_hdf5instdir}/lib64"
```

## Python version of the Python packages

The PGDG Python packages do not use the OS default Python everywhere: it
is Python 3.6 on RHEL 8, for instance. `%pgdg_python3_setup` defines
`python3_pkgversion` and `__python3` for the distribution, so the package
names (`python%{python3_pkgversion}-foo`) and all Python macros
(`%pyproject_wheel`, `%py3_build`, `%py_byte_compile`, `%python3_sitelib`,
...) use the same Python. Call it on the first line of the spec:

```spec
%pgdg_python3_setup

Name:		python%{python3_pkgversion}-foo
...
BuildRequires:	python%{python3_pkgversion}-devel
...
%build
%{__python3} setup.py build
```

| Distribution | `python3_pkgversion` | `__python3` |
| --- | --- | --- |
| Fedora 43 and 44 | `3.14` | `/usr/bin/python3.14` |
| Fedora 45 | `3.15` | `/usr/bin/python3.15` |
| RHEL 8, 9 and 10 | `3.12` | `/usr/bin/python3.12` |
| Amazon Linux 2023 | `3.13` | `/usr/bin/python3.13` |
| SLES 15 | `311` | `/usr/bin/python3.11` |
| SLES 16 | `313` | `/usr/bin/python3.13` |

On SLES 15, the macro also defines `pythons` as `python311` and
`python3_sitelib` as `%{_prefix}/lib/python3.11/site-packages`, so that the
SUSE pyproject macros build the python311 flavor instead of the default
python3 (3.6).

There is no way to opt out: every PGDG Python package uses this Python.

On any other distribution or release the build stops with an error: add it
to the macro first. Do not call the macro as `%{?pgdg_python3_setup}`:
without pgdg-srpm-macros, the build must fail rather than silently use the
OS default Python.

## Running tests in %check

The package being built is not installed into `%{pginstdir}` when `%check`
runs, so extension tests cannot simply run against the system's PostgreSQL.
`%pgdg_check_init` runs test servers from a copy of the PostgreSQL
installation instead, with the package's files from the build root on top.
The servers only listen on a unix socket in a private directory, so builds
running side by side cannot collide, and their superuser is called
`postgres`, as most upstream expected outputs assume. When `%check` ends,
successfully or not, every server is stopped; on failure, their logs are
printed first.

`initdb` refuses to run as root, so when the build runs as root,
`%pgdg_check_init` fails, rather than skipping the tests silently.

PGDG spec files keep their tests off by default, and they are run as a
separate process, with `--define 'runselftest 1'`. The PostgreSQL server
package then needs to be installed in the build root:

```spec
%{!?runselftest:%global runselftest 0}
...
%if %runselftest
BuildRequires:	postgresql%{pgmajorversion}-server
%endif
```

The common case, the upstream regression tests against a single server, is
one line. Anything following the macro is passed on to `make`:

```spec
%check
%if %runselftest
%pgdg_check_installcheck
%endif
```

Anything else uses `%pgdg_check_init`, followed by the shell functions it
loads:

| Function | Description |
|---|---|
| `pgdg_check_start NAME [SETTING...]` | Create and start a server; each `SETTING` is added to its `postgresql.conf`. The first server is the default one (`PGPORT`). |
| `pgdg_check_standby NAME PRIMARY [SETTING...]` | Create a streaming replication standby of `PRIMARY` with `pg_basebackup`, and start it. |
| `pgdg_check_port NAME` | Print the port of a server. |
| `pgdg_check_stop NAME` | Stop a server before the end of `%check`. |
| `pgdg_installcheck [MAKE ARGUMENT...]` | Run `make installcheck` against the default server, and print `regression.diffs` on failure. |

`PGHOST`, `PGUSER` and `PGPORT` are set for the default server, and the
copy's `bin` directory, `$PGDG_CHECK_BINDIR`, is first in `PATH`. For
instance, for an extension that needs to be preloaded:

```spec
%check
%if %runselftest
%pgdg_check_init
pgdg_check_start main "shared_preload_libraries = 'foo'"
pgdg_installcheck
psql -Atc "SELECT foo_status()" | grep -q '^ok$'
%endif
```

## License

PostgreSQL — see [LICENSE.txt](LICENSE.txt) for details.

## Maintainer

Devrim Gündüz &lt;devrim@gunduz.org&gt;
