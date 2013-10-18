#!/bin/sh
echo "1..1"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
perl $pmbp --root-dir-name="$tempdir" --install-module=Alien::RRDtool
libs=`perl $pmbp --root-dir-name="$tempdir" --print-libs`
#echo PERL5LIB=$libs
PERL5LIB="$libs" perl -MRRDs \
  -e '$RRDs::VERSION or die "No VERSION"' && \
  echo "ok 1" && \
  rm -fr $tempdir
