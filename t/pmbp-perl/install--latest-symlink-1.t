#!/bin/sh
echo "1..2"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

#XXX
PMBP_VERBOSE=10 \
perl $pmbp --root-dir-name "$tempdir" \
    --perl-version 5.12.0 \
    --install

touch "$tempdir/local/perl-5.12.0/hoge"

(ls "$tempdir/local/perl-latest/hoge" > /dev/null && echo "ok 1") || echo "not ok 1"

($tempdir/local/perlbrew/perls/perl-latest/bin/perl -e '$^V eq "v5.12.0" ? print "ok 2\n" : print "not ok 2\n"') || echo "not ok 2"

rm -fr $tempdir
