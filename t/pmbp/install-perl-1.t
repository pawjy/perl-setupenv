#!/bin/sh
echo "1..1"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

perl $pmbp --root-dir-name "$tempdir" \
    --perl-version 5.12.0 \
    --install-perl

local/perlbrew/perls/perl-5.12.0/bin/perl -e '$^V eq "v5.12.0" ? print "ok 1\n" : print "not ok 1\n"'

rm -fr $tempdir
