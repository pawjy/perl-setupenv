#!/bin/sh
echo "1..3"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
json=`echo $tempdir/local/perl-*/pmbp/tmp/pmtar/deps/CGI.pm-*.json`

perl $pmbp --root-dir-name="$tempdir" --scandeps=CGI::Carp

(ls $json > /dev/null && \
 grep FCGI $json > /dev/null && \
 echo "ok 1") || echo "not ok 1"

perl $pmbp --root-dir-name="$tempdir" --scandeps=CGI::Carp

(ls $json > /dev/null && \
 grep FCGI $json > /dev/null && \
 echo "ok 2") || echo "not ok 2"

libs=`perl $pmbp --root-dir-name="$tempdir" --print-libs`
perl -e '@INC = split /:/, shift; eval { use CGI::Carp } ? die "not ok 3\n" : print "ok 3\n"' "$libs" || exit 1

rm -fr $tempdir
