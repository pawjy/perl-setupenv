#!/bin/sh
echo "1..1"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
json=`echo $tempdir/deps/pmtar/deps/CGI.pm-*.json`

perl $pmbp --root-dir-name="$tempdir" \
    --install-module=CGI::Carp \
    --install-module=CGI \
    --write-libs-txt="$tempdir/libs.txt"

PERL5LIB="`cat $tempdir/libs.txt`" perl -MCGI -MCGI::Carp \
    -e 'print "ok 1\n"' || echo "not ok 1"

rm -fr $tempdir
