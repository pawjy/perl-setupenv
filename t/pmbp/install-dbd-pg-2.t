#!/bin/sh
echo "1..3"

#XXX
export PMBP_VERBOSE=10

basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
perl $pmbp --root-dir-name="$tempdir" $pmbp_pre_commands --install-perl --install-module=DBD::Pg \
  || echo "not ok 1"
libs=`perl $pmbp --root-dir-name="$tempdir" --print-libs`
#echo PERL5LIB=$libs
(PERL5LIB="$libs" perl -MDBD::Pg \
  -e '$'DBD::Pg'::VERSION or die "No VERSION"' && \
  echo "ok 1") || echo "not ok 1"

rm -fr $tempdir/local/perl-*/pm/lib/perl5/*/auto/DBD/Pg

(PERL5LIB="$libs" perl -MDBD::Pg \
  -e '$'DBD::Pg'::VERSION or die "No VERSION"' && \
  echo "not ok 2" && \
  rm -fr $tempdir) || echo "ok 2 # intentionally broken"

perl $pmbp --root-dir-name="$tempdir" $pmbp_pre_commands --install-module=DBD::Pg \
  || echo "not ok 3"
libs=`perl $pmbp --root-dir-name="$tempdir" --print-libs`
(PERL5LIB="$libs" perl -MDBD::Pg \
  -e '$'DBD::Pg'::VERSION or die "No VERSION"' && \
  echo "ok 3 # reinstall done" && \
  rm -fr $tempdir) || echo "not ok 3"
