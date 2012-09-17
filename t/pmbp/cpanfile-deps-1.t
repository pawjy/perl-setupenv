#!/bin/sh
echo "1..4"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p $tempdir
cp `dirname $0`/cpanfile-1.pl $tempdir/cpanfile

perl $pmbp --root-dir-name="$tempdir" \
    --select-modules-by-list \
    --write-install-module-index "$tempdir/install-modules.txt" \
    --write-pmb-install-list "$tempdir/pmb-install.txt"

(grep "Test::Differences" "$tempdir/install-modules.txt" > /dev/null && echo "ok 1") || echo "not ok 1"
(grep "CGI::Carp" "$tempdir/install-modules.txt" > /dev/null && echo "ok 2") || echo "not ok 2"

perl $pmbp --root-dir-name="$tempdir" \
    --read-module-index "$tempdir/install-modules.txt" \
    --set-module-index "$tempdir/install-modules.txt" \
    --install-modules-by-file-name "$tempdir/pmb-install.txt" \
    --write-libs-txt "$tempdir/libs.txt"

(
PERL5LIB="`cat $tempdir/libs.txt`" perl -MTest::Differences \
    -e 'die unless $Test::Differences::VERSION' && \
    echo "ok 3"
) || echo "not ok 3"
(
PERL5LIB="`cat $tempdir/libs.txt`" perl -MCGI::Carp \
    -e 'die unless $CGI::Carp::VERSION' && \
    echo "ok 4"
) || echo "not ok 4"

rm -fr $tempdir
