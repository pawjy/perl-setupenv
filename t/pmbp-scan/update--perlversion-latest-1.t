#!/bin/sh
echo "1..1"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p "$tempdir/config/perl"
echo latest > "$tempdir/config/perl/version.txt"

perl $pmbp --root-dir-name "$tempdir" \
    --update \
    --create-perl-command-shortcut perl

V=`perl $pmbp --root-dir-name "$tempdir" --print-selected-perl-version`
if [ -n "$V" ] && [ ! -x "$tempdir/local/perlbrew/perls/perl-$V/bin/perl" ]; then
  perl $pmbp --root-dir-name "$tempdir" --perl-version latest --install-perl
  perl $pmbp --root-dir-name "$tempdir" \
      --update \
      --create-perl-command-shortcut perl
fi

$tempdir/perl -MConfig -e 'my $v = shift; (sprintf "%vd", $^V) eq $v ? print "ok 1\n" : print "not ok 1 # got ".(sprintf "%vd",$^V)." expected $v\n"' "$V"

rm -fr $tempdir
