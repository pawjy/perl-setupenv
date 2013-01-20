#!/bin/sh
echo "1..2"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

(perl $pmbp --root-dir-name "$tempdir" \
    --install-module Text::MeCab \
    --create-perl-command-shortcut perl && echo "ok 1") || echo "not ok 1"

$tempdir/perl -MText::MeCab -e '
  $mecab = Text::MeCab->new;
  for ($node = $mecab->parse ("ねむいです。"); $node; $node = $node->next) {
    $result .= " " . $node->surface if defined $node->surface;
  }
  $result eq " ねむい です 。" ? print "ok 2\n" : die "not ok 2\n";
' || echo "not ok 2"

rm -fr $tempdir
