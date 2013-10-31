#!/bin/sh
echo "1..1"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
perl $pmbp --root-dir-name="$tempdir" \
    --perl-version latest --install-perl \
    --install-module=Image::Magick \
    --create-perl-command-shortcut perl
libs=`perl $pmbp --root-dir-name="$tempdir" --print-libs`
PERL5LIB="$libs" "$tempdir/perl" -MImage::Magick \
  -e '$Image::Magick::VERSION or die "No VERSION"' && \
  echo "ok 1" && \
  rm -fr $tempdir
