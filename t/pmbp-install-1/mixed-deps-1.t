#!/bin/sh
echo "1..7"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
srcdir=`dirname $0`/mixed-1

cp -r "$srcdir" "$tempdir"
perl $pmbp --root-dir-name="$tempdir" \
    --select-modules-by-list \
    --write-install-module-index "$tempdir/install-modules.txt" \
    --write-pmb-install-list "$tempdir/pmb-install.txt"

(grep Path::Class "$tempdir/pmb-install.txt" > /dev/null && echo "ok 1") || echo "not ok 1"
(grep CGI::Carp "$tempdir/pmb-install.txt" > /dev/null && echo "ok 2") || echo "not ok 2"
(grep Error "$tempdir/pmb-install.txt" > /dev/null && echo "ok 3") || echo "not ok 3"
(grep Log::Dispatch "$tempdir/pmb-install.txt" > /dev/null && echo "ok 4") || echo "not ok 4"
(grep Test::Name::FromLine "$tempdir/pmb-install.txt" > /dev/null && echo "ok 5") || echo "not ok 5"
(grep Scalar::Util::Instance "$tempdir/pmb-install.txt" > /dev/null && echo "ok 6") || echo "not ok 6"
(grep Exception::Class "$tempdir/pmb-install.txt" > /dev/null && echo "ok 7") || echo "not ok 7"

rm -fr $tempdir
