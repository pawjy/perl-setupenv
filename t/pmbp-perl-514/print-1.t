#!/bin/sh
echo "1..1"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

cd $tempdir

(perl $pmbp --root-dir-name "$tempdir" \
    --perl-version 5.12.0 \
    --print-actual-perl-version > x && echo "ok 1") || echo "not ok 1"

cat x

rm -fr $tempdir
