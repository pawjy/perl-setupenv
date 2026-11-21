#!/bin/sh
echo "1..2"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
mkdir -p "$tempdir"

(perl $pmbp --root-dir-name "$tempdir" \
    --perl-version latest \
    --print-actual-perl-version > "$tempdir/x" && echo "ok 1") || echo "not ok 1"

perl -e 'my $f = shift; open my $fh, "<", $f or die $!; local $/; my $v = <$fh>; $v =~ /\A5\.[0-9]+\.[0-9]+\s*\z/ ? print "ok 2\n" : print "not ok 2 # <$v>\n"' "$tempdir/x"

rm -fr $tempdir
