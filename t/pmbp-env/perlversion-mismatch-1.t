#!/bin/sh
echo "1..2"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p "$tempdir"

(perl $pmbp --root-dir-name "$tempdir" \
  --perl-version 5.14.0 --install-module Path::Class && echo "not ok 1") || echo "ok 1"

(ls $tempdir/local/perl-*/pm/lib/perl5/Path/Class.pm > /dev/null 2>&1 && echo "not ok 2") || echo "ok 2"

rm -fr $tempdir
