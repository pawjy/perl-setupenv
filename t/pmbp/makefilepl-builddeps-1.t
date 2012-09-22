#!/bin/sh
echo "1..2"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p $tempdir/lib $tempdir/bin
cp `dirname $0`/makefilepl-2.pl $tempdir/Makefile.PL
touch $tempdir/lib/Hoge.pm
touch $tempdir/bin/hoge

perl $pmbp --root-dir-name="$tempdir" \
    --select-modules-by-list \
    --write-install-module-index "$tempdir/install-modules.txt" \
    --write-pmb-install-list "$tempdir/pmb-install.txt"

(grep "Class::Accessor::Fast" "$tempdir/install-modules.txt" > /dev/null && echo "ok 1") || echo "not ok 1"
(grep "Test::Differences" "$tempdir/install-modules.txt" > /dev/null && echo "ok 2") || echo "not ok 2"

rm -fr $tempdir
