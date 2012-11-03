#!/bin/sh
echo "1..8"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p "$tempdir"

perl $pmbp --root-dir-name="$tempdir" \
    --print-pmtar-dir-name --print "
" > "$tempdir/result.txt"
echo "$tempdir/deps/pmtar" > "$tempdir/expected.txt"
(diff "$tempdir/result.txt" "$tempdir/expected.txt" && echo "ok 1") || echo "not ok 1"

perl $pmbp --root-dir-name="$tempdir" \
    --print-pmpp-dir-name --print "
" > "$tempdir/result.txt"
echo "$tempdir/deps/pmpp" > "$tempdir/expected.txt"
(diff "$tempdir/result.txt" "$tempdir/expected.txt" && echo "ok 2") || echo "not ok 2"

perl $pmbp --root-dir-name="$tempdir" \
    --pmtar-dir-name hoge/fuga \
    --print-pmtar-dir-name --print "
" > "$tempdir/result.txt"
echo "$tempdir/hoge/fuga" > "$tempdir/expected.txt"
(diff "$tempdir/result.txt" "$tempdir/expected.txt" && echo "ok 3") || echo "not ok 3"

perl $pmbp --root-dir-name="$tempdir" \
    --pmpp-dir-name hoge/fuga \
    --print-pmpp-dir-name --print "
" > "$tempdir/result.txt"
echo "$tempdir/hoge/fuga" > "$tempdir/expected.txt"
(diff "$tempdir/result.txt" "$tempdir/expected.txt" && echo "ok 4") || echo "not ok 4"

PMBP_PMTAR_DIR_NAME=abc \
perl $pmbp --root-dir-name="$tempdir" \
    --pmtar-dir-name hoge/fuga \
    --print-pmtar-dir-name --print "
" > "$tempdir/result.txt"
echo "$tempdir/hoge/fuga" > "$tempdir/expected.txt"
(diff "$tempdir/result.txt" "$tempdir/expected.txt" && echo "ok 5") || echo "not ok 5"

PMBP_PMPP_DIR_NAME=abc \
perl $pmbp --root-dir-name="$tempdir" \
    --pmpp-dir-name hoge/fuga \
    --print-pmpp-dir-name --print "
" > "$tempdir/result.txt"
echo "$tempdir/hoge/fuga" > "$tempdir/expected.txt"
(diff "$tempdir/result.txt" "$tempdir/expected.txt" && echo "ok 6") || echo "not ok 6"

PMBP_PMTAR_DIR_NAME=abc \
perl $pmbp --root-dir-name="$tempdir" \
    --print-pmtar-dir-name --print "
" > "$tempdir/result.txt"
echo "$tempdir/abc" > "$tempdir/expected.txt"
(diff "$tempdir/result.txt" "$tempdir/expected.txt" && echo "ok 7") || echo "not ok 7"

PMBP_PMPP_DIR_NAME=abc \
perl $pmbp --root-dir-name="$tempdir" \
    --print-pmpp-dir-name --print "
" > "$tempdir/result.txt"
echo "$tempdir/abc" > "$tempdir/expected.txt"
(diff "$tempdir/result.txt" "$tempdir/expected.txt" && echo "ok 8") || echo "not ok 8"

rm -fr $tempdir
