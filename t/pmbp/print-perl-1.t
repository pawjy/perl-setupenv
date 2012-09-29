#!/bin/sh
echo "1..1"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p "$tempdir"

perl $pmbp --print-perl-path > "$tempdir/path.txt"

perl -e 'local $/ = undef; <> =~ m{\A.+/perl\z} ? print "ok 1\n" : die "not ok 1\n"' "$tempdir/path.txt"

rm -fr $tempdir
