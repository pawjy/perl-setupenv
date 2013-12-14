#!/bin/sh
echo "1..2"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p "$tempdir/bin"

echo "warn \"ok 2\n\"" > "$tempdir/bin/hogehoge"
chmod u+x "$tempdir/bin/hogehoge"

perl $pmbp --root-dir-name "$tempdir" \
    --install \
    --create-perl-command-shortcut "abc=perl bin/hogehoge" && echo "ok 1"

# 2
$tempdir/abc

rm -fr $tempdir
