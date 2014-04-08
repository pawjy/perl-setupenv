#!/bin/sh
echo "1..6"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
tempdir2=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
inputtxt=$tempdir/input.txt
inputtxt2=$tempdir2/input.txt
packstxt=$tempdir/index.txt
listtxt=$tempdir/list.txt

mkdir -p $tempdir

echo CGI::Carp > $inputtxt
echo Test::Differences~0.49_02=http://backpan.perl.org/authors/id/O/OV/OVID/Test-Differences-0.49_02.tar.gz >> $inputtxt
echo Class::Registry~3.0=http://wakaba.github.com/packages/perl/Class-Registry-3.0.tar.gz >> $inputtxt

perl $pmbp --root-dir-name="$tempdir" \
    --select-modules-by-file-name "$inputtxt" \
    --write-module-index "$packstxt" \
    --write-pmb-install-list "$listtxt"

(grep "Test::Differences" "$listtxt" > /dev/null && echo "ok 1") || echo "not ok 1"
(grep "CGI::Carp" "$listtxt" > /dev/null && echo "ok 2") || echo "not ok 2"
(grep "Class::Registry" "$listtxt" > /dev/null && echo "ok 3") || echo "not ok 3"

mkdir -p $tempdir2

echo CGI::Carp > $inputtxt2
echo Test::Differences >> $inputtxt2
echo Class::Registry >> $inputtxt2

perl $pmbp --root-dir-name "$tempdir2" \
    --read-module-index "$packstxt" \
    --set-module-index "$packstxt" \
    --prepend-mirror "$tempdir/deps/pmtar" \
    --install-modules-by-file-name "$inputtxt2" \
    --write-libs-txt "$tempdir2/libs.txt"

(
PERL5LIB="`cat $tempdir2/libs.txt`" perl -MTest::Differences \
    -e 'die $Test::Differences::VERSION unless $Test::Differences::VERSION eq "0.49_02"' && \
    echo "ok 4"
) || echo "not ok 4"
(
PERL5LIB="`cat $tempdir2/libs.txt`" perl -MCGI::Carp \
    -e 'die unless $CGI::Carp::VERSION' && \
    echo "ok 5"
) || echo "not ok 5"
(
PERL5LIB="`cat $tempdir2/libs.txt`" perl -MClass::Registry \
    -e 'die $Class::Registry::VERSION unless $Class::Registry::VERSION eq "3.0"' && \
    echo "ok 6"
) || echo "not ok 6"

rm -fr $tempdir $tempdir2
