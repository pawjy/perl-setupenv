#!/bin/sh
echo "1..2"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p "$tempdir"

perl $pmbp --print-perl-path > "$tempdir/path.txt"

perl -e 'local $/ = undef; <> =~ m{\A.+/perl([0-9.]*)\z} ? print "ok 1\n" : die "not ok 1\n"' "$tempdir/path.txt"

perl $pmbp --perl-command="`which perl`" --print-perl-path > "$tempdir/path.txt" --preserve-info-file

perl -e 'local $/ = undef; <> =~ m{\A.+/perl([0-9.]*)\z} ? print "ok 2\n" : die "not ok 2\n"' "$tempdir/path.txt"

rm -fr $tempdir
