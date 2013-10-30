#!/bin/sh
echo "1..2"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
tempdir2=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
packstxt=$tempdir/list.txt

perl $pmbp --root-dir-name="$tempdir" \
    --select-module Class::Registry~3.0=http://wakaba.github.com/packages/perl/Class-Registry-3.0.tar.gz \
    --write-libs-txt "$tempdir/libs.txt" \
    --write-module-index "$tempdir/index.txt"

perl $pmbp --root-dir-name="$tempdir2" \
    --prepend-mirror "$tempdir/deps/pmtar" \
    --set-module-index "$tempdir/index.txt" \
    --install-module Class::Registry \
    --write-libs-txt "$tempdir2/libs.txt"

(
PERL5LIB="`cat $tempdir2/libs.txt`" perl -MClass::Registry \
    -e 'die $Class::Registry::VERSION unless $Class::Registry::VERSION eq "3.0"' && \
    echo "ok 1"
) || echo "not ok 1"

(ls $tempdir2/deps/pmtar/authors/id/misc/Class-Registry-3.0.tar.gz && echo "ok 2") || echo "not ok 2"

#rm -fr $tempdir $tempdir2
