#!/bin/sh
echo "1..8"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
tempdir2=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
inputtxt=$tempdir/input.txt
inputtxt2=$tempdir2/input.txt
packstxt=$tempdir/index.txt
listtxt=$tempdir/list.txt

mkdir -p $tempdir/config/perl
mkdir -p $tempdir/modules/hoge/config/perl
mkdir -p $tempdir/t_deps/modules/hoge/config/perl

echo CGI::Carp > $tempdir/config/perl/modules.txt
echo Test::Differences~0.49_02=http://backpan.perl.org/authors/id/O/OV/OVID/Test-Differences-0.49_02.tar.gz >> $tempdir/config/perl/modules.txt
echo Class::Registry~3.0=http://wakaba.github.com/packages/perl/Class-Registry-3.0.tar.gz > $tempdir/config/perl/modules.2.txt
echo Test::Class > $tempdir/t_deps/modules/hoge/config/perl/modules.tests.txt
echo Exporter::Lite > $tempdir/modules/hoge/config/perl/modules.txt

perl $pmbp --root-dir-name="$tempdir" \
    --select-modules-by-list \
    --write-module-index "$packstxt" \
    --write-pmb-install-list "$listtxt"

(grep "Test::Differences" "$listtxt" > /dev/null && echo "ok 1") || echo "not ok 1"
(grep "CGI::Carp" "$listtxt" > /dev/null && echo "ok 2") || echo "not ok 2"
(grep "Class::Registry" "$listtxt" > /dev/null && echo "ok 3") || echo "not ok 3"
(grep "Test::Class" "$listtxt" > /dev/null && echo "ok 4") || echo "not ok 4"
(grep "Exporter::Lite" "$listtxt" > /dev/null && echo "ok 5") || echo "not ok 5"

mkdir -p $tempdir2/config/perl

echo Class::Registry > $tempdir2/config/perl/modules.txt
echo Exporter::Lite >> $tempdir2/config/perl/modules.txt
echo Test::Differences > $tempdir2/config/perl/modules.tests.txt

perl $pmbp --root-dir-name "$tempdir2" \
    --read-module-index "$packstxt" \
    --set-module-index "$packstxt" \
    --prepend-mirror "$tempdir/deps/pmtar" \
    --install-modules-by-list \
    --write-libs-txt "$tempdir2/libs.txt"

(
PERL5LIB="`cat $tempdir2/libs.txt`" perl -MTest::Differences \
    -e 'die $Test::Differences::VERSION unless $Test::Differences::VERSION eq "0.49_02"' && \
    echo "ok 6"
) || echo "not ok 6"
(
PERL5LIB="`cat $tempdir2/libs.txt`" perl -MExporter::Lite \
    -e 'die unless $Exporter::Lite::VERSION' && \
    echo "ok 7"
) || echo "not ok 7"
(
PERL5LIB="`cat $tempdir2/libs.txt`" perl -MClass::Registry \
    -e 'die $Class::Registry::VERSION unless $Class::Registry::VERSION eq "3.0"' && \
    echo "ok 8"
) || echo "not ok 8"

rm -fr $tempdir $tempdir2
