#!/bin/sh
echo "1..6"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
srcdir=`dirname $0`/scanpms-1

mkdir -p $tempdir
perl $pmbp --root-dir-name="$tempdir" \
    --print-scanned-dependency $srcdir > "$tempdir/list.txt"

(grep Path::Class "$tempdir/list.txt" > /dev/null && echo "ok 1") || echo "not ok 1"
(grep Exporter::Lite "$tempdir/list.txt" > /dev/null && echo "ok 2") || echo "not ok 2"
(grep Carp "$tempdir/list.txt" > /dev/null && echo "ok 3") || echo "not ok 3"
(grep CGI "$tempdir/list.txt" > /dev/null && echo "not ok 4") || echo "ok 4"
(grep Hoge "$tempdir/list.txt" > /dev/null && echo "not ok 5") || echo "ok 5"
(grep Submod1 "$tempdir/list.txt" > /dev/null && echo "not ok 6") || echo "ok 6"

rm -fr $tempdir
