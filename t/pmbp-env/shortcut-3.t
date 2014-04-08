#!/bin/sh
echo "1..2"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p "$tempdir/deps/pmpp/bin"

echo "echo \"ok 2\"" > "$tempdir/deps/pmpp/bin/hogehoge"
chmod u+x "$tempdir/deps/pmpp/bin/hogehoge"

perl $pmbp --root-dir-name "$tempdir" \
    --install \
    --create-perl-command-shortcut "$tempdir/fuga/hogehoge" && echo "ok 1"

cat $tempdir/fuga/hogehoge

# 2
$tempdir/fuga/hogehoge

rm -fr $tempdir
