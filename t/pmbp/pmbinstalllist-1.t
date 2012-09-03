#!/bin/sh
echo "1..13"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
pmbitxt=$tempdir/pmb-install.txt
pmbindextxt=$tempdir/install.index

perl $pmbp --root-dir-name="$tempdir" \
    --read-module-index "$tempdir/index.txt" \
    --select-module DBI --select-module Test::mysqld \
    --write-module-index "$tempdir/index.txt" \
    --write-pmb-install-list "$pmbitxt"

(grep DBI~ "$pmbitxt" > /dev/null || (echo "not ok 1" && false)) && echo "ok 1"
(grep Test::mysqld~ "$pmbitxt" > /dev/null || (echo "not ok 2" && false)) && echo "ok 2"
(grep Test::Requires~ "$pmbitxt" > /dev/null || (echo "not ok 3" && false)) && echo "ok 3"

perl $pmbp --root-dir-name="$tempdir" \
    --read-module-index "$tempdir/index.txt" \
    --select-module DBI --select-module Test::mysqld \
    --select-module Path::Class \
    --write-module-index "$tempdir/index.txt" \
    --write-pmb-install-list "$pmbitxt"

(grep Path::Class~ "$pmbitxt" > /dev/null || (echo "not ok 4" && false)) && echo "ok 4"
(grep K/KW/KWILLIAMS/Path-Class "$pmbitxt" > /dev/null || (echo "ok 5" && false)) && echo "not ok 5"
(grep DBI~ "$pmbitxt" > /dev/null || (echo "not ok 6" && false)) && echo "ok 6"
(grep Test::mysqld~ "$pmbitxt" > /dev/null || (echo "not ok 7" && false)) && echo "ok 7"
(grep Test::Requires~ "$pmbitxt" > /dev/null || (echo "not ok 8" && false)) && echo "ok 8"

perl $pmbp --root-dir-name="$tempdir" \
    --read-module-index "$tempdir/index.txt" \
    --select-module CGI::Carp \
    --write-module-index "$tempdir/index.txt" \
    --write-pmb-install-list "$pmbitxt"

(grep CGI~ "$pmbitxt" > /dev/null || (echo "not ok 9" && false)) && echo "ok 9"
(grep Path::Class "$pmbitxt" > /dev/null || (echo "ok 10" && false)) && echo "not ok 10"
(grep DBI~ "$pmbitxt" > /dev/null || (echo "ok 11" && false)) && echo "not ok 11"

perl $pmbp --root-dir-name="$tempdir" \
    --read-module-index "$tempdir/index.txt" \
    --select-module Path::Class \
    --write-install-module-index "$pmbindextxt"

(grep Path::Class "$pmbindextxt" > /dev/null || (echo "not ok 12" && false)) && echo "ok 12"
(grep K/KW/KWILLIAMS/Path-Class "$pmbindextxt" > /dev/null || (echo "not ok 13" && false)) && echo "ok 13"

rm -fr $tempdir
