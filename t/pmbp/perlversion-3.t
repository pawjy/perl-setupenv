#!/bin/sh
echo "1..1"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p "$tempdir"
touch "$tempdir/version.txt"

(perl $pmbp --root-dir-name "$tempdir" \
    --perl-version-by-file-name "$tempdir/version.txt" \
    --print-selected-perl-version && echo "not ok 1") || echo "ok 1"

rm -fr $tempdir
