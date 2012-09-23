#!/bin/sh
echo "1..4"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
packstxt=$tempdir/list.txt
pmbtxt=$tempdir/install.txt

perl $pmbp --root-dir-name="$tempdir" \
    --read-module-index="$packstxt" \
    --select-module Pod::Usage \
    --write-module-index="$packstxt" \
    --write-pmb-install-list "$pmbtxt"

(grep Pod::Usage "$packstxt" > /dev/null && echo "ok 1") || echo "not ok 1"
(grep Pod::Usage "$pmbtxt" > /dev/null && echo "ok 2") || echo "not ok 2"
(grep Pod-Parser "$packstxt" > /dev/null && echo "ok 3") || echo "not ok 3"

perl $pmbp --root-dir-name "$tempdir" \
  --read-module-index "$packstxt" --set-module-index "$packstxt" \
  --install-module Pod::Usage

perl $pmbp --root-dir-name "$tempdir" \
  --read-module-index "$packstxt" --set-module-index "$packstxt" \
  --install-module Pod::Usage

PERL5LIB="`perl $pmbp --root-dir-name \"$tempdir\" --print-libs`" \
    perl -MPod::Usage -e '$Pod::Usage::VERSION ? print "ok 4\n" : die "not ok 4\n"' || echo "not ok 4"

rm -fr $tempdir
