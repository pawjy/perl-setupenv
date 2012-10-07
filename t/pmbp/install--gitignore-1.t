#!/bin/sh
echo "1..7"
basedir=$(cd `dirname $0`/../.. && pwd)
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p "$tempdir"
cd "$tempdir"
git init
touch "$tempdir/hogefuga"
touch "$tempdir/hogefuga2"

perl $pmbp --root-dir-name "$tempdir" \
    --install \
    --add-to-gitignore hogefuga

(GIT_DIR="$tempdir/.git" git status | grep "hogefuga$" > /dev/null && echo "not ok 1") || echo "ok 1"
(GIT_DIR="$tempdir/.git" git status | grep "hogefuga2" > /dev/null && echo "ok 2") || echo "not ok 2"
(GIT_DIR="$tempdir/.git" git status | grep "config/perl/libs.txt" > /dev/null && echo "not ok 3") || echo "ok 3"

rm -fr $tempdir
