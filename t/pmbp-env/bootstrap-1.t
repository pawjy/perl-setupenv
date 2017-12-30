#!/bin/sh
echo "1..2"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p "$tempdir"
echo 'cd $(dirname $0)' > $tempdir/template
echo '{{INSTALL}}' >> $tempdir/template
echo 'perl local/bin/pmbp.pl --create-perl-command-shortcut perl' >> $tempdir/template

perl $pmbp --root-dir-name "$tempdir" \
    --create-bootstrap-script "$tempdir/template $tempdir/result"

(ls "$tempdir/result" > /dev/null && echo "ok 1") || echo "not ok 1"

bash "$tempdir/result"

$tempdir/perl -e 'print "ok 2\n"' || echo "not ok 2"

rm -fr $tempdir
