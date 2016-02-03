#!/bin/sh
echo "1..2"
basedir=$(cd `dirname $0`/../.. && pwd)
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p $tempdir/foo
cd $tempdir/foo

# XXX
which perl

((perl $pmbp --install-perl
             --install-openssl \
             --install-module Net::SSLeay \
             --create-perl-command-shortcut which \
             --create-perl-command-shortcut perl && echo "ok 1") || echo "not ok 1")

# XXX
which perl
./which perl
./perl -v

(./perl -MNet::SSLeay -e '+Net::SSLeay::SSLeay_version ()' && echo "ok 2") || echo "not ok 2"

cd
rm -fr $tempdir
