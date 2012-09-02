#!/bin/sh
echo "1..3"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
perl $pmbp --root-dir-name="$tempdir" --scandeps=CGI::Carp
json=`echo $tempdir/local/perl-*/pmbp/tmp/pmtar/deps/CGI.pm-*.json`
ls $json || (echo "not ok 1" && exit 1)
grep FCGI $json > /dev/null || (echo "not ok 1" && exit 1)
echo "ok 1"

perl $pmbp --root-dir-name="$tempdir" --scandeps=CGI::Carp
ls $json || (echo "not ok 1" && exit 1)
grep FCGI $json > /dev/null || (echo "not ok 2" && exit 1)
echo "ok 2"

libs=`perl $pmbp --root-dir-name="$tempdir" --print-libs`
#echo PERL5LIB=$libs
perl -e '@INC = split /:/, shift; eval { use CGI::Carp } ? die "not ok 3\n" : print "ok 3\n"' "$libs" || exit 1

rm -fr $tempdir
