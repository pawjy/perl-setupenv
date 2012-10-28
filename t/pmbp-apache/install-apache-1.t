#!/bin/sh
echo "1..2"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

(perl $pmbp --root-dir-name "$tempdir" \
    --install-apache 2.4 && echo "ok 1") || echo "not ok 1"

(ls "$tempdir/local/apache/httpd-2.4/bin/httpd" > /dev/null && echo "ok 2") || echo "not ok 2"

rm -fr $tempdir
