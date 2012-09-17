#!/bin/sh
echo "1..3"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
packstxt=$tempdir/list.txt

perl $pmbp --root-dir-name="$tempdir" \
    --install-module Test::Differences~0.49_02=http://backpan.perl.org/authors/id/O/OV/OVID/Test-Differences-0.49_02.tar.gz \
    --write-libs-txt "$tempdir/libs.txt"

(
PERL5LIB="`cat $tempdir/libs.txt`" perl -MTest::Differences \
    -e 'die $Test::Differences::VERSION unless $Test::Differences::VERSION eq "0.49_02"' && \
    echo "ok 1"
) || echo "not ok 1"

perl $pmbp --root-dir-name="$tempdir" \
    --install-module Test::Differences=http://backpan.perl.org/authors/id/O/OV/OVID/Test-Differences-0.49_02.tar.gz \
    --write-libs-txt "$tempdir/libs.txt"

(
PERL5LIB="`cat $tempdir/libs.txt`" perl -MTest::Differences \
    -e 'die $Test::Differences::VERSION unless $Test::Differences::VERSION eq "0.49_02"' && \
    echo "ok 2"
) || echo "not ok 2"

(ls $tempdir/deps/pmtar/authors/id/O/OV/OVID/Test-Differences-0.49_02.tar.gz && echo "ok 3") || echo "not ok 3"

rm -fr $tempdir
