#!/bin/sh
echo "1..2"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p "$tempdir"

perl $pmbp --root-dir-name "$tempdir" --print-latest-perl-version > "$tempdir/version.txt"

perl -e '<> =~ /^5\.\d+\.\d+$/ ? print "ok 1\n" : print "not ok 1\n"' < "$tempdir/version.txt"

perl $pmbp --root-dir-name "$tempdir" --print-perl-archname > "$tempdir/archname.txt"

touch "$tempdir/empty.txt"

(diff "$tempdir/archname.txt" "$tempdir/empty.txt" > /dev/null && echo "not ok 2") || echo "ok 2"

rm -fr $tempdir
