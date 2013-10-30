#!/bin/sh
echo "1..3"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
packstxt=$tempdir/list.txt
inputtxt=$tempdir/input.txt

mkdir -p $tempdir

echo CGI::Carp > $inputtxt
echo Test::Differences~0.49_02=http://backpan.perl.org/authors/id/O/OV/OVID/Test-Differences-0.49_02.tar.gz >> $inputtxt
echo Class::Registry~3.0=http://wakaba.github.com/packages/perl/Class-Registry-3.0.tar.gz >> $inputtxt

perl $pmbp --root-dir-name="$tempdir" \
    --install-modules-by-file-name "$inputtxt" \
    --write-libs-txt "$tempdir/libs.txt"

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

rm -fr $tempdir
