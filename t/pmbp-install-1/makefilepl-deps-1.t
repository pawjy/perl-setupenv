#!/bin/sh
echo "1..10"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p $tempdir
cp `dirname $0`/makefilepl-1.pl $tempdir/Makefile.PL

perl $pmbp --root-dir-name="$tempdir" \
    --select-modules-by-list \
    --write-install-module-index "$tempdir/install-modules.txt" \
    --write-pmb-install-list "$tempdir/pmb-install.txt"

(grep "Test::Name::FromLine" "$tempdir/install-modules.txt" > /dev/null && echo "ok 1") || echo "not ok 1"
(grep "Scalar::Util::Numeric" "$tempdir/install-modules.txt" > /dev/null && echo "ok 2") || echo "not ok 2"
(grep "Module::Install" "$tempdir/install-modules.txt" > /dev/null && echo "ok 3") || echo "ok 3 # skip"
(grep "Module::Install::AuthorTests" "$tempdir/install-modules.txt" > /dev/null && echo "ok 4") || echo "ok 4 # skip"

(grep "Test::Name::FromLine" "$tempdir/pmb-install.txt" > /dev/null && echo "ok 5") || echo "not ok 5"
(grep "Scalar::Util::Numeric" "$tempdir/pmb-install.txt" > /dev/null && echo "ok 6") || echo "not ok 6"
(grep "Module::Install" "$tempdir/pmb-install.txt" > /dev/null && echo "ok 7") || echo "ok 7 # skip"
(grep "Module::Install::AuthorTests" "$tempdir/pmb-install.txt" > /dev/null && echo "ok 8") || echo "ok 8 # skip"

perl $pmbp --root-dir-name="$tempdir" \
    --read-module-index "$tempdir/install-modules.txt" \
    --set-module-index "$tempdir/install-modules.txt" \
    --install-modules-by-file-name "$tempdir/pmb-install.txt" \
    --write-libs-txt "$tempdir/libs.txt"

(
PERL5LIB="`cat $tempdir/libs.txt`" perl -MTest::Name::FromLine \
    -e 'die unless $Test::Name::FromLine::VERSION' && \
    echo "ok 9"
) || echo "not ok 9"
(
PERL5LIB="`cat $tempdir/libs.txt`" perl -MScalar::Util::Numeric \
    -e 'die unless $Scalar::Util::Numeric::VERSION' && \
    echo "ok 10"
) || echo "not ok 10"

rm -fr $tempdir
