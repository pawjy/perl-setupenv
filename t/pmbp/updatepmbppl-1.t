#!/bin/sh
echo "1..3"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

perl $pmbp --root-dir-name="$tempdir" \
    --update-pmbp-pl

(perl $tempdir/local/bin/pmbp.pl --root-dir-name "$tempdir" \
     --update-pmbp-pl && echo "ok 1") || echo "not ok 1"

(perl $tempdir/local/bin/pmbp.pl --root-dir-name "$tempdir" \
     --print-pmbp-pl-etag > "$tempdir/etag.txt" && echo "ok 2") || echo "not ok 2"

touch "$tempdir/empty.txt"

(diff "$tempdir/etag.txt" "$tempdir/empty.txt" && echo "not ok 3") || echo "ok 3"

rm -fr $tempdir
