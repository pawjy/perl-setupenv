#!/bin/sh
echo "1..3"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
packstxt=$tempdir/list.txt

perl $pmbp --root-dir-name="$tempdir" \
    --install-module Class::Registry~3.0=http://wakaba.github.com/packages/perl/Class-Registry-3.0.tar.gz \
    --write-libs-txt "$tempdir/libs.txt"

(
PERL5LIB="`cat $tempdir/libs.txt`" perl -MClass::Registry \
    -e 'die $Class::Registry::VERSION unless $Class::Registry::VERSION eq "3.0"' && \
    echo "ok 1"
) || echo "not ok 1"

perl $pmbp --root-dir-name="$tempdir" \
    --install-module Class::Registry~3.0=http://wakaba.github.com/packages/perl/Class-Registry-3.0.tar.gz \
    --write-libs-txt "$tempdir/libs.txt"

(
PERL5LIB="`cat $tempdir/libs.txt`" perl -MClass::Registry \
    -e 'die $Class::Registry::VERSION unless $Class::Registry::VERSION eq "3.0"' && \
    echo "ok 2"
) || echo "not ok 2"

(ls $tempdir/local/perl-*/pmbp/tmp/pmtar/authors/id/misc/Class-Registry-3.0.tar.gz && echo "ok 3") || echo "not ok 3"

rm -fr $tempdir
