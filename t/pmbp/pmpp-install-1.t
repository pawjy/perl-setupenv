#!/bin/sh
echo "1..5"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

perl $pmbp --root-dir-name="$tempdir" \
    --install-to-pmpp DBIx::RewriteDSN

perl $pmbp --root-dir-name "$tempdir" \
    --install-module DBIx::RewriteDSN

perllibs=`perl $pmbp --root-dir-name "$tempdir" --print-libs`

PERL5LIB=$perllibs perl -MDBIx::RewriteDSN \
    -e '$DBIx::RewriteDSN::VERSION ? print "ok 1\n" : die "not ok 1\n"' || echo "not ok 1"

(ls $tempdir/deps/pmpp/lib/perl5/DBIx/RewriteDSN.pm > /dev/null && echo "ok 2") || echo "not ok 2"
(ls $tempdir/local/perl-*/pm/lib/perl5/DBIx/RewriteDSN.pm > /dev/null && echo "ok 3") || echo "not ok 3"
(ls $tempdir/deps/pmpp/lib/perl5/*/DBI.pm > /dev/null && echo "not ok 4") || echo "ok 4"
(ls $tempdir/local/perl-*/pm/lib/perl5/*/DBI.pm > /dev/null && echo "ok 5") || echo "not ok 5"

rm -fr $tempdir
