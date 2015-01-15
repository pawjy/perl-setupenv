#!/bin/sh
echo "1..3"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
srcdir=`dirname $0`/scanpms-1

mkdir -p $tempdir/bin $tempdir/config/perl

echo "use strict; use Path::Class;\nuse Foo::Bar;" > $tempdir/bin/hoge.pl
echo "- Path::Class\n-Foo::Bar" > $tempdir/config/perl/pmbp-exclusions.txt

result=$tempdir/hoge.txt
perl $pmbp --root-dir-name="$tempdir" \
    --read-pmbp-exclusions-txt="$tempdir/config/perl/pmbp-exclusions.txt" \
    --select-modules-by-list --write-install-module-index="$result"

(ls "$result" > /dev/null && echo "ok 1") || echo "not ok 1"
(grep Path::Class "$result" > /dev/null && echo "not ok 2") || echo "ok 2"
(grep Foo::Bar "$result" > /dev/null && echo "not ok 3") || echo "ok 3"

rm -fr $tempdir
