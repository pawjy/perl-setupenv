#!/bin/sh
echo "1..2"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
tempdir2=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
packstxt=$tempdir/list.txt

perl $pmbp --root-dir-name="$tempdir" \
    --select-module Test::Differences~0.49_02=http://backpan.perl.org/authors/id/O/OV/OVID/Test-Differences-0.49_02.tar.gz \
    --write-libs-txt "$tempdir/libs.txt" \
    --write-module-index "$tempdir/index.txt"

perl $pmbp --root-dir-name="$tempdir2" \
    --set-module-index "$tempdir/index.txt" \
    --install-module Test::Differences \
    --write-libs-txt "$tempdir2/libs.txt"

(
PERL5LIB="`cat $tempdir2/libs.txt`" perl -MTest::Differences \
    -e 'die $Test::Differences::VERSION unless $Test::Differences::VERSION eq "0.49_02"' && \
    echo "ok 1"
) || echo "not ok 1"

(ls $tempdir2/deps/pmtar/authors/id/O/OV/OVID/Test-Differences-0.49_02.tar.gz && echo "ok 2") || echo "not ok 2"

rm -fr $tempdir $tempdir2
