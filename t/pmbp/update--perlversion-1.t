#!/bin/sh
echo "1..1"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p "$tempdir/config/perl"
echo 5.14.0 > "$tempdir/config/perl/version.txt"

perl $pmbp --root-dir-name "$tempdir" \
    --update

(PERL5LIB="`cat \"$tempdir/config/perl/libs.txt\"`" \
    perl -e '$^V eq "5.14.0" ? print "ok 1\n" : print "not ok 1\n"') || echo "not ok 1"

rm -fr $tempdir
