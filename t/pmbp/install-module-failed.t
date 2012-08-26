#!/bin/sh
echo "1..1"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
perl $pmbp \
  --root-dir-name="$tempdir" \
  --install-module=Module::Not::Found || \
echo "ok 1"
rm -fr $tempdir
