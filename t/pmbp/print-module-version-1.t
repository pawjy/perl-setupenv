#!/bin/sh
echo "1..1"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

perl $pmbp --root-dir-name "$tempdir" --install-module Error

perl $pmbp --root-dir-name "$tempdir" \
    --print-module-version Data::Dumper --print "
" --print-module-version Mo::duLe_nO::tfou_nd --print "
" --print-module-version Error --print "
" --print-module-version Encode --print "
---" > "$tempdir/versions.txt"

perl -e 'local $/ = undef; <> =~ /^.+\n\n.+\n.+\n---$/ ? print "ok 1\n" : die "not ok 1\n"' "$tempdir/versions.txt"

rm -fr $tempdir
