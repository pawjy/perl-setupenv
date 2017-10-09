#!/bin/sh
echo "1..2"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

perl $pmbp --root-dir-name "$tempdir" \
    --install-module Test::Exception \
    --create-perl-command-shortcut "@p1=perl" && echo "ok 1"

$tempdir/p1 -MTest::Exception -e '$Test::Exception::VERSION ? print "ok 2\n" : print "not ok 2\n"'

rm -fr $tempdir
