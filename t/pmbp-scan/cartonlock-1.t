#!/bin/sh
echo "1..2"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p $tempdir
cp `dirname $0`/carton-lock-1.json $tempdir/carton.lock

perl $pmbp --root-dir-name="$tempdir" \
    --read-carton-lock "$tempdir/carton.lock" \
    --write-module-index "$tempdir/modules.txt"

perl $pmbp --root-dir-name="$tempdir" \
    --read-module-index "$tempdir/modules.txt" \
    --set-module-index "$tempdir/modules.txt" \
    --select-modules-by-list \
    --write-install-module-index "$tempdir/install-modules.txt" \
    --write-pmb-install-list "$tempdir/pmb-install.txt"

perl $pmbp --root-dir-name="$tempdir" \
    --read-module-index "$tempdir/install-modules.txt" \
    --set-module-index "$tempdir/install-modules.txt" \
    --install-modules-by-file-name "$tempdir/pmb-install.txt" \
    --write-libs-txt "$tempdir/libs.txt"

(
PERL5LIB="`cat $tempdir/libs.txt`" perl -MAnyEvent \
    -e 'die $AnyEvent::VERSION unless $AnyEvent::VERSION >= "7.0"' && \
    echo "ok 1"
) || echo "not ok 1"
(
PERL5LIB="`cat $tempdir/libs.txt`" perl -MLWP::UserAgent \
    -e 'die $LWP::UserAgent::VERSION unless $LWP::UserAgent::VERSION >= "6.04"' && \
    echo "ok 2"
) || echo "not ok 2"

rm -fr $tempdir
