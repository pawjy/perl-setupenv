#!/bin/sh
echo "1..2"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

(perl $pmbp \
   --verbose --verbose \
   --root-dir-name="$tempdir" \
   --install-module=List::Rubyish && \
 echo "ok 1") || echo "not ok 1"

(PERL5LIB="`perl $pmbp --root-dir-name "$tempdir" --print-libs`" \
 perl -e 'use List::Rubyish' && echo "ok 2") || echo "not ok 2"

rm -fr $tempdir
