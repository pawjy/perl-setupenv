#!/bin/sh
echo "1..3"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

(perl $pmbp --root-dir-name "$tempdir" \
    --perl-version latest \
    --install && echo "ok 1") || echo "not ok 1"

V=`perl $pmbp --root-dir-name "$tempdir" --perl-version latest --print-actual-perl-version`
if [ -n "$V" ] && [ ! -x "$tempdir/local/perlbrew/perls/perl-$V/bin/perl" ]; then
  perl $pmbp --root-dir-name "$tempdir" --perl-version latest --install-perl
  perl $pmbp --root-dir-name "$tempdir" --perl-version latest --install
fi

if [ -z "$V" ]; then
  echo "not ok 2 # no version"
  echo "not ok 3 # no version"
else
  touch "$tempdir/local/perl-$V/hoge"
  (ls "$tempdir/local/perl-latest/hoge" > /dev/null && echo "ok 2") || echo "not ok 2"

  ("$tempdir/local/perlbrew/perls/perl-latest/bin/perl" -e 'print "ok 3\n"') || echo "not ok 3"
fi

rm -fr $tempdir
