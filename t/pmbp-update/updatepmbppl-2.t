#!/bin/sh
echo "1..1"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

perl $pmbp --root-dir-name="$tempdir" \
    --update-pmbp-pl-staging

(perl $tempdir/local/bin/pmbp.pl --root-dir-name "$tempdir" \
     --update-pmbp-pl-staging && echo "ok 1") || echo "not ok 1"

rm -fr $tempdir
