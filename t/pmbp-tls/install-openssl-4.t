#!/bin/sh
echo "1..5"
basedir=$(cd `dirname $0`/../.. && pwd)
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p "$tempdir"

((perl $pmbp --root-dir-name "$tempdir" \
             --install-module Net::SSLeay \
             --create-perl-command-shortcut which \
             --create-perl-command-shortcut perl && echo "ok 1") || echo "not ok 1")

($tempdir/perl -MNet::SSLeay -e 'print +Net::SSLeay::SSLeay_version ()' > $tempdir/version2.txt && echo "ok 2") || echo "not ok 2"

perl $pmbp --root-dir-name "$tempdir" \
    --print-openssl-version > $tempdir/version.txt
touch $tempdir/empty.txt
(diff -u $tempdir/version.txt $tempdir/empty.txt && echo "not ok 3") || echo "ok 3"
(diff -u $tempdir/version2.txt $tempdir/version.txt && echo "ok 4") || echo "not ok 4"

perl -e ' print (<> =~ /OpenSSL 0\./ ? "not ok 5\n" : "ok 5\n") ' < $tempdir/version.txt

rm -fr "$tempdir"
