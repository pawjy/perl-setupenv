#!/bin/sh
echo "1..2"
basedir=$(cd `dirname $0`/../.. && pwd)
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p $tempdir/foo
cd $tempdir/foo

((perl $pmbp --install-openssl \
             --install-module Net::SSLeay \
             --create-perl-command-shortcut perl && echo "ok 1") || echo "not ok 1")

(./perl -MNet::SSLeay -e 'print $Net::SSLeay::VERSION' && echo "ok 2") || echo "not ok 2"

cd
rm -fr $tempdir
