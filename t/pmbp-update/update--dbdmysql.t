#!/bin/sh
echo "1..3"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p "$tempdir/config/perl"
echo "DBD::mysql" > "$tempdir/config/perl/modules.txt"

perl $pmbp --root-dir-name "$tempdir" \
    --update

(grep DBD::mysql $tempdir/deps/pmtar/modules/index.txt > /dev/null && echo "ok 1") || echo "not ok 1"
(grep DBD::mysql $tempdir/config/perl/pmb-install.txt > /dev/null && echo "ok 2") || echo "not ok 2"

perl $pmbp --root-dir-name "$tempdir" --install

(PERL5LIB="`cat \"$tempdir/config/perl/libs.txt\"`" \
    perl -e 'use DBD::mysql' && echo "ok 3") || echo "not ok 3"

rm -fr $tempdir
