#!/bin/sh
echo "1..3"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
json=`echo $tempdir/deps/pmtar/deps/DBD-mysql-*.json`

perl $pmbp --root-dir-name="$tempdir" --scandeps=DBD::mysql

(ls $json > /dev/null && \
 grep DBD::mysql $json > /dev/null && \
 echo "ok 1") || echo "not ok 1"

perl $pmbp --root-dir-name="$tempdir" --scandeps=DBD::mysql

(ls $json > /dev/null && \
 grep DBD::mysql $json > /dev/null && \
 echo "ok 2") || echo "not ok 2"

libs=`perl $pmbp --root-dir-name="$tempdir" --print-libs`
perl -e '@INC = split /:/, shift; eval q{ use DBD::mysql } ? die "not ok 3\n" : print "ok 3\n"' "$libs" || exit 1

rm -fr $tempdir
