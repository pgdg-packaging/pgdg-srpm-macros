#  -*- Mode: sh; indent-tabs-mode: t -*-
#  shellcheck shell=bash
#  SPDX-License-Identifier: PostgreSQL
#
#  This file is part of PostgreSQL Global Development Group RPM Packages
#
#  Copyright 2026 Devrim Gündüz <devrim@gunduz.org>

# Shell functions for running PostgreSQL servers in the %check section of
# PGDG spec files. They are loaded by the %pgdg_check_init macro, which is
# what spec files use; see README.md.
#
# The package being built is not installed into %{pginstdir} when %check
# runs, so the servers run from a copy of the PostgreSQL installation, with
# the package's files from the build root on top. PostgreSQL is relocatable:
# the server, pg_config and pg_regress in the copy all use the copy.
#
# The servers only listen on a unix socket in a private directory, so builds
# running side by side cannot collide, and their superuser is called
# postgres, as most upstream expected outputs assume. When the %check
# section exits, successfully or not, every server is stopped; on failure,
# their logs are printed first.

# Usage: pgdg_check_init PGINSTDIR BUILDROOT
# Prepares the copy of the PostgreSQL installation, and sets PGHOST, PGUSER
# and PATH up for it.
pgdg_check_init() {
	PGDG_CHECK_DIR=$(pwd)/pgdg_check
	PGDG_CHECK_INSTDIR=$PGDG_CHECK_DIR/pginst
	PGDG_CHECK_BINDIR=$PGDG_CHECK_INSTDIR/bin
	PGDG_CHECK_SOCKDIR=$(mktemp -d)
	PGDG_CHECK_SERVERS=
	PGDG_CHECK_NEXTPORT=54321

	rm -rf "$PGDG_CHECK_DIR"
	mkdir -p "$PGDG_CHECK_DIR"
	cp -a "$1" "$PGDG_CHECK_INSTDIR" || return 1
	if [ -d "$2$1" ]; then
		cp -a "$2$1/." "$PGDG_CHECK_INSTDIR/" || return 1
	fi

	export PGHOST=$PGDG_CHECK_SOCKDIR PGUSER=postgres
	export PATH=$PGDG_CHECK_BINDIR:$PATH
	unset PGPORT PGDATABASE PGDATA
	trap pgdg_check_cleanup EXIT
}

# Usage: pgdg_check_start NAME [SETTING...]
# Creates and starts a server called NAME. Each SETTING, e.g.
# "shared_preload_libraries = 'foo'", is added to its postgresql.conf. The
# first server started is the default one, PGPORT points at it.
pgdg_check_start() {
	local name=$1
	shift

	"$PGDG_CHECK_BINDIR/initdb" -D "$PGDG_CHECK_DIR/$name" -U postgres -A trust --no-sync \
		>"$PGDG_CHECK_DIR/$name.initdb.log" 2>&1 || {
		cat "$PGDG_CHECK_DIR/$name.initdb.log"
		return 1
	}
	pgdg_check_configure "$name" "$@" && pgdg_check_pgctl_start "$name"
}

# Usage: pgdg_check_standby NAME PRIMARY [SETTING...]
# Creates a streaming replication standby of the server PRIMARY with
# pg_basebackup, and starts it. The SETTINGs are added to its
# postgresql.conf, after the ones copied over from PRIMARY.
pgdg_check_standby() {
	local name=$1 primary=$2
	shift 2

	"$PGDG_CHECK_BINDIR/pg_basebackup" -D "$PGDG_CHECK_DIR/$name" -R -X stream \
		-p "$(pgdg_check_port "$primary")" || return 1
	pgdg_check_configure "$name" "$@" && pgdg_check_pgctl_start "$name"
}

# Usage: pgdg_check_port NAME
# Prints the port of the server NAME, e.g. for psql -p.
pgdg_check_port() {
	cat "$PGDG_CHECK_DIR/$1.port"
}

# Usage: pgdg_check_stop NAME
# Stops the server NAME. There is no need to call this at the end of %check.
pgdg_check_stop() {
	local name remaining=

	"$PGDG_CHECK_BINDIR/pg_ctl" -D "$PGDG_CHECK_DIR/$1" -m fast -w stop >/dev/null || return 1
	for name in $PGDG_CHECK_SERVERS; do
		[ "$name" = "$1" ] || remaining="$remaining $name"
	done
	PGDG_CHECK_SERVERS=$remaining
}

# Usage: pgdg_installcheck [MAKE ARGUMENT...]
# Runs "make installcheck" in the current directory against the default
# server, and prints regression.diffs when it fails.
pgdg_installcheck() {
	${MAKE:-make} installcheck USE_PGXS=1 PG_CONFIG="$PGDG_CHECK_BINDIR/pg_config" "$@" && return 0
	find . -name regression.diffs -not -path './pgdg_check/*' -printf '===== %p\n' -exec cat {} \;
	return 1
}

# Internal functions

pgdg_check_configure() {
	local name=$1 port=$PGDG_CHECK_NEXTPORT setting
	shift

	PGDG_CHECK_NEXTPORT=$((port + 1))
	{
		echo
		echo "# Added by pgdg_check"
		echo "listen_addresses = ''"
		echo "unix_socket_directories = '$PGDG_CHECK_SOCKDIR'"
		echo "port = $port"
		echo "fsync = off"
		# PGDG's postgresql.conf turns the logging collector on, which would
		# keep the server's messages out of the log printed on failure
		echo "logging_collector = off"
		for setting in "$@"; do
			echo "$setting"
		done
	} >>"$PGDG_CHECK_DIR/$name/postgresql.conf"
	echo "$port" >"$PGDG_CHECK_DIR/$name.port"
	if [ -z "$PGDG_CHECK_SERVERS" ]; then
		export PGPORT=$port
	fi
}

pgdg_check_pgctl_start() {
	# Register the server first, so that it is stopped even if pg_ctl gives
	# up waiting for it
	PGDG_CHECK_SERVERS="$PGDG_CHECK_SERVERS $1"
	"$PGDG_CHECK_BINDIR/pg_ctl" -D "$PGDG_CHECK_DIR/$1" -l "$PGDG_CHECK_DIR/$1.log" -w -t 120 start >/dev/null
}

pgdg_check_cleanup() {
	local rc=$? name mode=fast reversed=

	# Print all the logs before stopping anything, so that a standby's log
	# does not end with complaints about its primary going away
	if [ $rc -ne 0 ]; then
		mode=immediate
		for name in $PGDG_CHECK_SERVERS; do
			if [ -f "$PGDG_CHECK_DIR/$name.log" ]; then
				echo "===== server log of $name"
				cat "$PGDG_CHECK_DIR/$name.log"
			fi
		done
	fi
	# Stop the servers in reverse order, standbys before their primaries
	for name in $PGDG_CHECK_SERVERS; do
		reversed="$name $reversed"
	done
	for name in $reversed; do
		"$PGDG_CHECK_BINDIR/pg_ctl" -D "$PGDG_CHECK_DIR/$name" -m $mode -w stop >/dev/null 2>&1 || :
	done
	rm -rf "$PGDG_CHECK_SOCKDIR"
	[ $rc -ne 0 ] || rm -rf "$PGDG_CHECK_DIR"
	exit $rc
}
