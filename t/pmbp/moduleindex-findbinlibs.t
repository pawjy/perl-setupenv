#!/bin/sh
echo "1..3"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
packstxt=$tempdir/list.txt
pmbtxt=$tempdir/install.txt

perl $pmbp --root-dir-name="$tempdir" \
    --read-module-index="$packstxt" \
    --select-module FindBin::libs \
    --write-module-index="$packstxt" \
    --write-pmb-install-list "$pmbtxt"

(grep FindBin::libs "$packstxt" > /dev/null && echo "ok 1") || echo "not ok 1"
(grep FindBin::libs "$pmbtxt" > /dev/null && echo "ok 2") || echo "not ok 2"
(grep FindBin-libs "$packstxt" > /dev/null && echo "ok 3") || echo "not ok 3"

rm -fr $tempdir
