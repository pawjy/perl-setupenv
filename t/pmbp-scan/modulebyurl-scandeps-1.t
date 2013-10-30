#!/bin/sh
echo "1..11"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
packstxt=$tempdir/list.txt

perl $pmbp --root-dir-name="$tempdir" \
    --scandeps Test::Differences~0.49_02=http://backpan.perl.org/authors/id/O/OV/OVID/Test-Differences-0.49_02.tar.gz

(ls $tempdir/deps/pmtar/authors/id/O/OV/OVID/Test-Differences-0.49_02.tar.gz && echo "ok 1") || echo "not ok 1"

(
PERL5LIB="`cat $tempdir/libs.txt`" perl -MTest::Differences \
    -e 'die $Test::Differences::VERSION unless $Test::Differences::VERSION eq "0.49_02"' && \
    echo "not ok 2"
) || echo "ok 2"

depsjson=`ls $tempdir/deps/pmtar/deps/Test-Differences-0.49_02.json`
(grep "\"distvname\" : \"Test-Differences-0.49_02\"" "$depsjson" > /dev/null \
    && echo "ok 3") || echo "not ok 3"
(grep "\"package\" : \"Test::Differences\"" "$depsjson" > /dev/null \
    && echo "ok 4") || echo "not ok 4"
(grep "\"pathname\" : \"O/OV/OVID/Test-Differences-0.49_02.tar.gz\"" "$depsjson" > /dev/null \
    && echo "ok 5") || echo "not ok 5"
(grep "\"version\" : \"0.49_02\"" "$depsjson" > /dev/null \
    && echo "ok 6") || echo "not ok 6"
(grep "\"package\" : \"Text::Diff\"" "$depsjson" > /dev/null \
    && echo "ok 7") || echo "not ok 7"

perl $pmbp --root-dir-name="$tempdir" \
    --scandeps Test::Differences~0.49_02=http://backpan.perl.org/authors/id/O/OV/OVID/Test-Differences-0.49_02.tar.gz \
    --write-module-index "$tempdir/modules.txt"

(grep "Test::Differences" "$tempdir/modules.txt" > /dev/null \
    && echo "ok 8") || echo "not ok 8"
(grep "O/OV/OVID/Test-Differences-0.49_02.tar.gz" "$tempdir/modules.txt" > /dev/null \
    && echo "ok 9") || echo "not ok 9"

perl $pmbp --root-dir-name="$tempdir" \
    --read-module-index "$tempdir/modules.txt" \
    --select-module Test::Differences~0.49_02=http://backpan.perl.org/authors/id/O/OV/OVID/Test-Differences-0.49_02.tar.gz \
    --write-pmb-install-list "$tempdir/pmb-modules.txt"

(grep "Test::Differences~0.49_02" "$tempdir/pmb-modules.txt" > /dev/null \
    && echo "ok 10") || echo "not ok 10"
(grep "Text::Diff" "$tempdir/pmb-modules.txt" > /dev/null \
    && echo "ok 11") || echo "not ok 11"

rm -fr $tempdir
