#!/bin/sh
echo "1..3"
basedir=$(cd `dirname $0`/../.. && pwd)
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

(perl $pmbp --root-dir-name $tempdir/foo --init-git-repository && echo "ok 1") || echo "not ok 1"
(ls $tempdir/foo/.git/config > /dev/null && echo "ok 2") || echo "not ok 2"

(perl $pmbp --root-dir-name $tempdir/foo --init-git-repository && echo "ok 3") || echo "not ok 3"

rm -fr $tempdir
