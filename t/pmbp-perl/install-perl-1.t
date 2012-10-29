#!/bin/sh
echo "1..4"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

(perl $pmbp --root-dir-name "$tempdir" \
    --perl-version 5.12.0 \
    --install-perl && echo "ok 1") || echo "not ok 1"

($tempdir/local/perlbrew/perls/perl-5.12.0/bin/perl -e '$^V eq "v5.12.0" ? print "ok 2\n" : print "not ok 2\n"') || echo "not ok 2"

PATH=$tempdir/local/perlbrew/perls/perl-5.12.0/bin:$PATH perl $pmbp \
    --root-dir-name "$tempdir" --perl-version 5.12.0 \
    --create-perl-command-shortcut perl

$tempdir/perl -e '(sprintf "%vd", $^V) eq "5.12.0" ? print "ok 3\n" : print "not ok 3"'

($tempdir/local/perlbrew/perls/perl-latest/bin/perl -e '$^V eq "v5.12.0" ? print "ok 4\n" : print "not ok 4\n"') || echo "not ok 4"

rm -fr $tempdir
