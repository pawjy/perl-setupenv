#!/bin/sh
echo "1..2"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
json=`echo $tempdir/deps/pmtar/deps/CGI.pm-*.json`

perl $pmbp --root-dir-name="$tempdir" \
    --select-module=CGI::Carp \
    --select-module=CGI \
    --write-libs-txt="$tempdir/libs.txt" \
    --write-module-index="$tempdir/index.txt"

(grep "CGI-" "$tempdir/index.txt" > /dev/null && echo "ok 1") || echo "not ok 1"
(grep "CGI::Carp " "$tempdir/index.txt" > /dev/null && echo "ok 2") || echo "not ok 2"

rm -fr $tempdir
