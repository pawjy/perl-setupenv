#!/bin/sh
echo "1..10"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
pmbitxt=$tempdir/pmb-install.txt

perl $pmbp --root-dir-name="$tempdir" \
    --read-package-list "$tempdir/index.txt" \
    --select-module DBI --select-module Test::mysqld \
    --write-package-list "$tempdir/index.txt" \
    --write-pmb-install-list "$pmbitxt"

(grep DBI~ "$pmbitxt" > /dev/null || (echo "not ok 1" && false)) && echo "ok 1"
(grep Test::mysqld~ "$pmbitxt" > /dev/null || (echo "not ok 2" && false)) && echo "ok 2"
(grep Test::Requires~ "$pmbitxt" > /dev/null || (echo "not ok 3" && false)) && echo "ok 3"

perl $pmbp --root-dir-name="$tempdir" \
    --read-package-list "$tempdir/index.txt" \
    --select-module DBI --select-module Test::mysqld \
    --select-module Path::Class \
    --write-package-list "$tempdir/index.txt" \
    --write-pmb-install-list "$pmbitxt"

(grep Path::Class~ "$pmbitxt" > /dev/null || (echo "not ok 4" && false)) && echo "ok 4"
(grep DBI~ "$pmbitxt" > /dev/null || (echo "not ok 5" && false)) && echo "ok 5"
(grep Test::mysqld~ "$pmbitxt" > /dev/null || (echo "not ok 6" && false)) && echo "ok 6"
(grep Test::Requires~ "$pmbitxt" > /dev/null || (echo "not ok 7" && false)) && echo "ok 7"

perl $pmbp --root-dir-name="$tempdir" \
    --read-package-list "$tempdir/index.txt" \
    --select-module CGI::Carp \
    --write-package-list "$tempdir/index.txt" \
    --write-pmb-install-list "$pmbitxt"

(grep CGI~ "$pmbitxt" > /dev/null || (echo "not ok 8" && false)) && echo "ok 8"
(grep Path::Class~ "$pmbitxt" > /dev/null || (echo "ok 9" && false)) && echo "not ok 9"
(grep DBI~ "$pmbitxt" > /dev/null || (echo "ok 10" && false)) && echo "not ok 10"

rm -fr $tempdir
