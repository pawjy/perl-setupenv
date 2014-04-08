#!/bin/sh
echo "1..2"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p "$tempdir"

PMBP_VERBOSE=10 perl $pmbp 2> "$tempdir/log.txt"

perl -e 'local $/ = undef; <> =~ m{^\@INC = }m ? print "ok 1\n" : die "not ok 1\n"' "$tempdir/log.txt"
perl -e 'local $/ = undef; <> =~ m{^Done: }m ? print "ok 2\n" : die "not ok 2\n"' "$tempdir/log.txt"

rm -fr $tempdir
