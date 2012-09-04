#!/bin/sh
echo "1..10"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
packstxt=$tempdir/list.txt

perl $pmbp --root-dir-name="$tempdir" \
    --read-module-index="$packstxt" \
    --scandeps Exporter::Lite \
    --scandeps CGI::Carp \
    --write-module-index="$packstxt"

(grep CGI::Carp "$packstxt" > /dev/null && echo "ok 1") || echo "not ok 1"
(grep CGI.pm- "$packstxt" > /dev/null && echo "ok 2") || echo "not ok 2"
(grep Exporter::Lite "$packstxt" > /dev/null && echo "ok 3") || echo "not ok 3"
(grep Exporter-Lite- "$packstxt" > /dev/null && echo "ok 4") || echo "not ok 4"

perl $pmbp --root-dir-name="$tempdir" \
    --read-module-index="$packstxt" \
    --scandeps Try::Tiny \
    --write-module-index="$packstxt"

(grep CGI::Carp "$packstxt" > /dev/null && echo "ok 5") || echo "not ok 5"
(grep Try::Tiny "$packstxt" > /dev/null && echo "ok 6") || echo "not ok 6"

perl $pmbp --root-dir-name="$tempdir" \
    --read-module-index="$packstxt" \
    --scandeps Module::Not::Found::A \
    --write-module-index="$packstxt" && echo "not ok 7" || echo "ok 7"

(grep CGI::Carp "$packstxt" > /dev/null && echo "ok 8") || echo "not ok 8"
(grep Try::Tiny "$packstxt" > /dev/null && echo "ok 9") || echo "not ok 9"
(grep Not::Found::A "$packstxt" > /dev/null && echo "not ok 10") || echo "ok 10"

rm -fr $tempdir
