#!/bin/sh
echo "1..1"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

perl $pmbp --root-dir-name "$tempdir" \
    --perl-version 5.12.0 \
    --install

touch "$tempdir/local/perl-5.12.0/hoge"

(ls "$tempdir/local/perl-latest/hoge" > /dev/null && echo "ok 1") || echo "not ok 1"

rm -fr $tempdir
