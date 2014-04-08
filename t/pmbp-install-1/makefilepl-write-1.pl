#!/bin/sh
echo "1..1"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p $tempdir/config/perl
echo "CGI::Carp~1.0" > $tempdir/config/perl/pmb-install.txt

perl $pmbp --write-makefile-pl "$tempdir/Makefile.PL"

perl $pmbp --root-dir-name "$tempdir" --install-module Module::Install \
  --write-libs-txt "$tempdir/libs.txt"

cd $tempdir

PERL5LIB="`cat libs.txt`" perl Makefile.PL

(grep CGI::Carp MYMETA.json > /dev/null && echo "ok 1") || echo "not ok 1"

cd ..

rm -fr $tempdir
