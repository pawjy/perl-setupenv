#!/bin/sh
echo "1..6"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p "$tempdir/config/perl"

echo "perl
prove
local/bin/which=which
#plackup

myapp=bin/myapp.pl
" > "$tempdir/config/perl/pmbp-shortcuts.txt"

perl $pmbp --root-dir-name "$tempdir" \
    --install

(ls "$tempdir/perl" > /dev/null && echo "ok 1") || echo "not ok 1"
(ls "$tempdir/prove" > /dev/null && echo "ok 2") || echo "not ok 2"
(ls "$tempdir/#plackup" > /dev/null && echo "not ok 3") || echo "ok 3"
(ls "$tempdir/local/bin/which" > /dev/null && echo "ok 4") || echo "not ok 4"
(ls "$tempdir/myapp" > /dev/null && echo "ok 5") || echo "not ok 5"

("$tempdir/perl" -e 'exit 0' && echo "ok 6") || echo "not ok 6"

rm -fr $tempdir
