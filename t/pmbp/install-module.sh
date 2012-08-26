#!/bin/sh
echo "1..1"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
perl $pmbp \
  --root-dir-name="$tempdir" \
  --install-module=$1
PERL5LIB="`perl $pmbp --print-libs`" perl -M$1 \
  -e '$'$1'::VERSION or die "No VERSION"' && \
  echo "ok 1" && \
  rm -fr $tempdir
