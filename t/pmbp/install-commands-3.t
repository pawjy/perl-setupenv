#!/bin/sh
echo "1..1"
basedir=$(cd `dirname $0`/../.. && pwd)
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p $tempdir/foo
cd $tempdir/foo && \
((perl $pmbp --install-commands "" && echo "ok 1") || echo "not ok 1")

rm -fr $tempdir
