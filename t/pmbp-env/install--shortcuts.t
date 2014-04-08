#!/bin/sh
echo "1..4"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p "$tempdir"

perl $pmbp --root-dir-name "$tempdir" \
    --install

(ls "$tempdir/local/bin/perl" > /dev/null && echo "ok 1") || echo "not ok 1"
(ls "$tempdir/local/bin/perldoc" > /dev/null && echo "ok 2") || echo "not ok 2"
(ls "$tempdir/local/bin/prove" > /dev/null && echo "ok 3") || echo "not ok 3"

("$tempdir/local/bin/perl" -e 'exit 0' && echo "ok 4") || echo "not ok 4"

rm -fr $tempdir
