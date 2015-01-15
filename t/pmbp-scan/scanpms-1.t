#!/bin/sh
echo "1..1"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
srcdir=`dirname $0`/scanpms-1

mkdir -p $tempdir/bin

echo "use strict; use Path::Class;" > $tempdir/bin/hoge.pl

result=$tempdir/hoge.txt
perl $pmbp --root-dir-name="$tempdir" \
    --select-modules-by-list --write-install-module-index="$result"

(grep Path::Class "$result" > /dev/null && echo "ok 1") || echo "not ok 1"

rm -fr $tempdir
