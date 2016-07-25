#!/bin/sh
echo "1..1"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
(perl $pmbp --root-dir-name="$tempdir" \
    --perl-version 5.20.0 \
    --install-perl \
    --install-module=Image::Magick \
    --create-perl-command-shortcut perl && echo "ok 1") || echo "not ok 1"
libs=`perl $pmbp --root-dir-name="$tempdir" --print-libs`
PERL5LIB="$libs" "$tempdir/perl" -MImage::Magick -e '' #XXX && echo "ok 1" 

rm -fr $tempdir
