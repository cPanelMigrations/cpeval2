#! /bin/sh

usage() {
    [ -n "$1" ] && echo "$1" 1>&2
    echo "usage: $0 bundle dir" 1>&2
    echo "       $0 --list bundle" 1>&2
    exit 1
}

die() {
    echo "$0: $@" 1>&2
    exit 1
}

extract() {
    perl -ne 'if (/^__DATA__$/) { $data=1; next; } print if $data' | openssl enc -base64 -d | gzip -d
}

[ $# -lt 2 ] && usage

if [ "$1" = "--list" ]; then
    extract < "$2" | tar tf -
    exit 0
fi

BUNDLE="$1"
DIR="$2"

if [ ! -f "$BUNDLE" ]; then
    die "Could not find bundle $BUNDLE"
fi

if [ ! -d "$DIR" ]; then
    mkdir "$DIR" || exit 1
fi

extract < "$BUNDLE" | (cd "$DIR"; tar pxf -)
