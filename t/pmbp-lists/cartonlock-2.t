#!/bin/sh
echo "1..3"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p $tempdir
cp `dirname $0`/carton-lock-2.json $tempdir/carton.lock

perl $pmbp --root-dir-name="$tempdir" \
    --read-carton-lock "$tempdir/carton.lock" \
    --write-module-index "$tempdir/modules.txt" && echo "ok 1"

perl $pmbp --root-dir-name="$tempdir" \
    --read-module-index "$tempdir/modules.txt" \
    --set-module-index "$tempdir/modules.txt" \
    --select-modules-by-list \
    --write-install-module-index "$tempdir/install-modules.txt" \
    --write-pmb-install-list "$tempdir/pmb-install.txt" && echo "ok 2"

perl $pmbp --root-dir-name="$tempdir" \
    --read-module-index "$tempdir/install-modules.txt" \
    --set-module-index "$tempdir/install-modules.txt" \
    --install-modules-by-file-name "$tempdir/pmb-install.txt" \
    --write-libs-txt "$tempdir/libs.txt" && echo "ok 3"

rm -fr $tempdir
