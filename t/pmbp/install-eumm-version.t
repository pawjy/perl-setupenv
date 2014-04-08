#!/bin/sh
echo "1..2"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

perl $pmbp --root-dir-name "$tempdir" \
    --install-module ExtUtils::MakeMaker=$(perl $pmbp --print-cpan-top-url)authors/id/M/MS/MSCHWERN/ExtUtils-MakeMaker-6.63_02.tar.gz \
    --install-module List::Rubyish \
    --write-libs-txt "$tempdir/libs.txt" && \
echo "ok 1"

(
PERL5LIB="`cat $tempdir/libs.txt`" perl -MList::Rubyish \
    -e 'die unless $List::Rubyish::VERSION' && \
    echo "ok 2"
) || echo "not ok 2"

rm -fr $tempdir
