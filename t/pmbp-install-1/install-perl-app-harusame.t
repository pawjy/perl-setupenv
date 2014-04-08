#!/bin/sh
echo "1..1"
basedir=$(cd `dirname $0`/../.. && pwd)
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p "$tempdir"

perl $pmbp --root-dir-name "$tempdir" \
    --install-perl-app https://github.com/wakaba/harusame#2b442d4b5da7ee8666c394c3ad6d59e66e5d9d4d
perl $pmbp --root-dir-name "$tempdir/local/harusame" \
    --install-module Path::Class \
    --create-perl-command-shortcut harusame=bin/harusame.pl

($tempdir/local/harusame/harusame --help > /dev/null && echo "ok 1") || echo "not ok 1"

rm -fr "$tempdir"
