#!/bin/sh
echo "1..5"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p "$tempdir/config/perl"
echo latest > "$tempdir/config/perl/version.txt"
echo "Test::Class" > "$tempdir/config/perl/modules.txt"

perl $pmbp --root-dir-name "$tempdir" \
    --install \
    --create-perl-command-shortcut perl

V=`perl $pmbp --root-dir-name "$tempdir" --print-selected-perl-version`
if [ -n "$V" ] && [ ! -x "$tempdir/local/perlbrew/perls/perl-$V/bin/perl" ]; then
  perl $pmbp --root-dir-name "$tempdir" --perl-version latest --install-perl
  perl $pmbp --root-dir-name "$tempdir" \
      --install \
      --create-perl-command-shortcut perl
fi

(ls "$tempdir/config/perl/libs.txt" > /dev/null && echo "ok 1") || echo "not ok 1"
perl -e "-f '$tempdir/config/perl/libs.txt' ? print qq{ok 2\n} : print qq{not ok 2\n}"

($tempdir/perl -e 'use Test::Class' && echo "ok 3") || echo "not ok 3"
($tempdir/perl -MConfig -e 'my $v = shift; (sprintf "%vd", $^V) eq $v ? print "ok 4\n" : print "not ok 4 # got ".(sprintf "%vd",$^V)." expected $v\n"' "$V") || echo "not ok 4"

(ls "$tempdir/local/perl-$V/pm/lib/perl5/Test/Class.pm" > /dev/null && echo "ok 5") || echo "not ok 5"

rm -fr $tempdir
