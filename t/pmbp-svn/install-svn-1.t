#!/bin/sh
echo "1..3"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

(perl $pmbp --root-dir-name "$tempdir" \
    --install-svn && echo "ok 1") || echo "not ok 1"

(ls "$tempdir/local/apache/svn/bin/svn" > /dev/null && echo "ok 2") || echo "not ok 2"

(($tempdir/local/apache/svn/bin/svn help) && echo "ok 3") || echo "not ok 3"

rm -fr $tempdir
