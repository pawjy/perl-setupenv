#!/bin/sh
echo "1..2"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
packstxt=$tempdir/list.txt
pmbtxt=$tempdir/install.txt

perl $pmbp --root-dir-name="$tempdir" \
    --read-module-index="$packstxt" \
    --select-module Class::Accessor::Lite \
    --write-module-index="$packstxt" \
    --write-pmb-install-list "$pmbtxt"

(grep Class::Accessor::Lite "$packstxt" > /dev/null && echo "ok 1") || echo "not ok 1"
(grep Class::Accessor::Lite "$pmbtxt" > /dev/null && echo "ok 2") || echo "not ok 2"

rm -fr $tempdir
