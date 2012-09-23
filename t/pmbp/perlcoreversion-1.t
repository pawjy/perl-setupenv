#!/bin/sh
echo "1..1"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p "$tempdir"

perl $pmbp --root-dir-name "$tempdir" --print-perl-core-version Test::More > "$tempdir/version.txt"

perl -e '<> eq "5.006002" ? print "ok 1\n" : print "not ok 1\n"' < "$tempdir/version.txt"

rm -fr $tempdir
