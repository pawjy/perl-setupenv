#!/bin/sh
echo "1..1"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

perl $pmbp --root-dir-name="$tempdir" \
    --select-module Net::SSLeay \
    --write-pmb-install-list "$tempdir/list.txt"

perl $pmbp --root-dir-name "$tempdir" \
    --update-pmpp-by-file-name "$tempdir/list.txt"

(ls "$tempdir/deps/pmpp/lib/perl5/`perl -MConfig -e 'print $Config{archname}'`/Net/SSLeay.pm" > /dev/null && echo "ok 1") || echo "not ok 1"

rm -fr $tempdir
