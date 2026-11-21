#!/bin/sh
echo "1..2"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p "$tempdir/local/perl-latest/fuga"

perl $pmbp --root-dir-name "$tempdir" \
    --perl-version 5.12.0 \
    --install

touch "$tempdir/local/perl-5.12.0/hoge"

(ls "$tempdir/local/perl-latest/hoge" > /dev/null && echo "ok 1") || echo "not ok 1"
(ls "$tempdir/local/perl-latest/fuga" 2> /dev/null && echo "not ok 2") || echo "ok 2"

rm -fr $tempdir
