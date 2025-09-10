#!/bin/sh
echo "1..1"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
perl $pmbp --root-dir-name="$tempdir" $pmbp_pre_commands --install-module=$1 \
     --create-perl-command-shortcut=perl \
  || echo "not ok 1"
libs=`perl $pmbp --root-dir-name="$tempdir" --print-libs`
#echo PERL5LIB=$libs
($tempdir/perl -M$1 \
  -e '$'$1'::VERSION or die "No VERSION"' && \
  echo "ok 1" && \
  rm -fr $tempdir) || echo "not ok 1"
