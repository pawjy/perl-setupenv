#!/bin/sh
echo "1..2"
basedir=$(cd `dirname $0`/../.. && pwd)
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p "$tempdir"

((PMBP_VERBOSE=10 perl $pmbp --root-dir-name "$tempdir" \
             --install-openssl \
             --install-module Net::SSLeay \
             --create-perl-command-shortcut perl && echo "ok 1") || echo "not ok 1")

($tempdir/perl -MNet::SSLeay -e 'warn +Net::SSLeay::SSLeay_version ()' && echo "ok 2") || echo "not ok 2"

rm -fr "$tempdir"
