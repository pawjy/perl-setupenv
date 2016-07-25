#!/bin/sh
echo "1..3"
basedir=$(cd `dirname $0`/../.. && pwd)
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p "$tempdir"

((perl $pmbp --root-dir-name "$tempdir" \
             --install-openssl-if-mac \
             --install-module Net::SSLeay \
             --create-perl-command-shortcut which \
             --create-perl-command-shortcut perl && echo "ok 1") || echo "not ok 1")

($tempdir/perl -MNet::SSLeay -e 'warn +Net::SSLeay::SSLeay_version ()' && echo "ok 2") || echo "not ok 2"

perl $pmbp --root-dir-name "$tempdir" \
    --print-openssl-version > $tempdir/version.txt
touch $tempdir/empty.txt
(diff -u $tempdir/version.txt $tempdir/empty.txt && echo "not ok 3") || echo "ok 3"

rm -fr "$tempdir"
