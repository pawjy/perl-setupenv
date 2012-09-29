#!/bin/sh
echo "1..5"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
packstxt=$tempdir/list.txt

mkdir -p $tempdir/config/perl
mkdir -p $tempdir/modules/hoge/config/perl
mkdir -p $tempdir/t_deps/modules/hoge/config/perl

echo CGI::Carp > $tempdir/config/perl/modules.txt
echo Test::Differences~0.49_02=http://backpan.perl.org/authors/id/O/OV/OVID/Test-Differences-0.49_02.tar.gz >> $tempdir/config/perl/modules.txt
echo Class::Registry~3.0=http://wakaba.github.com/packages/perl/Class-Registry-3.0.tar.gz > $tempdir/config/perl/modules.2.txt
echo Test::Class > $tempdir/t_deps/modules/hoge/config/perl/modules.tests.txt
echo Exporter::Lite > $tempdir/modules/hoge/config/perl/modules.txt

perl $pmbp --root-dir-name="$tempdir" \
    --install-modules-by-list \
    --write-libs-txt "$tempdir/libs.txt" --verbose

cat "$tempdir/libs.txt"

(
PERL5LIB="`cat $tempdir/libs.txt`" perl -MTest::Differences \
    -e 'die $Test::Differences::VERSION unless $Test::Differences::VERSION eq "0.49_02"' && \
    echo "ok 1"
) || echo "not ok 1"
(
PERL5LIB="`cat $tempdir/libs.txt`" perl -MCGI::Carp \
    -e 'die unless $CGI::Carp::VERSION' && \
    echo "ok 2"
) || echo "not ok 2"
(
PERL5LIB="`cat $tempdir/libs.txt`" perl -MClass::Registry \
    -e 'die $Class::Registry::VERSION unless $Class::Registry::VERSION eq "3.0"' && \
    echo "ok 3"
) || echo "not ok 3"
(
PERL5LIB="`cat $tempdir/libs.txt`" perl -MExporter::Lite \
    -e 'die unless $Exporter::Lite::VERSION' && \
    echo "ok 4"
) || echo "not ok 4"
(
PERL5LIB="`cat $tempdir/libs.txt`" perl -MTest::More \
    -e 'die unless $Test::More::VERSION' && \
    echo "ok 5"
) || echo "not ok 5"

rm -fr $tempdir
