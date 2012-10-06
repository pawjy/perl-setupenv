#!/bin/sh
echo "1..1"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p "$tempdir"
echo latest > "$tempdir/version.txt"

perl $pmbp --root-dir-name "$tempdir" \
    --perl-version-by-file-name "$tempdir/version.txt" \
    --print-selected-perl-version > "$tempdir/selversion.txt"

perl $pmbp --root-dir-name "$tempdir" \
    --perl-version latest \
    --print-selected-perl-version > "$tempdir/latestversion.txt"

(diff "$tempdir/selversion.txt" "$tempdir/latestversion.txt" && echo "ok 1") || echo "not ok 1"

rm -fr $tempdir
