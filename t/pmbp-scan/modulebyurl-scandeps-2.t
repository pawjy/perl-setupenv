#!/bin/sh
echo "1..11"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
packstxt=$tempdir/list.txt

perl $pmbp --root-dir-name="$tempdir" \
    --scandeps Class::Registry~3.0=http://wakaba.github.com/packages/perl/Class-Registry-3.0.tar.gz

(ls $tempdir/deps/pmtar/authors/id/misc/Class-Registry-3.0.tar.gz && echo "ok 1") || echo "not ok 1"

(
PERL5LIB="`cat $tempdir/libs.txt`" perl -MClass::Registry \
    -e 'die $Class::Registry::VERSION unless $Class::Registry::VERSION eq "3.0"' && \
    echo "not ok 2"
) || echo "ok 2"

depsjson=`ls $tempdir/deps/pmtar/deps/Class-Registry-3.0.json`
(grep "\"distvname\" : \"Class-Registry-3.0\"" "$depsjson" > /dev/null \
    && echo "ok 3") || echo "not ok 3"
(grep "\"package\" : \"Class::Registry\"" "$depsjson" > /dev/null \
    && echo "ok 4") || echo "not ok 4"
(grep "\"pathname\" : \"misc/Class-Registry-3.0.tar.gz\"" "$depsjson" > /dev/null \
    && echo "ok 5") || echo "not ok 5"
(grep "\"version\" : \"3.0\"" "$depsjson" > /dev/null \
    && echo "ok 6") || echo "not ok 6"
(grep "\"package\" : \"Class::Registry\"" "$depsjson" > /dev/null \
    && echo "ok 7") || echo "not ok 7"

perl $pmbp --root-dir-name="$tempdir" \
    --scandeps Class::Registry~3.0=http://wakaba.github.com/packages/perl/Class-Registry-3.0.tar.gz \
    --write-module-index "$tempdir/modules.txt"

(grep "Class::Registry" "$tempdir/modules.txt" > /dev/null \
    && echo "ok 8") || echo "not ok 8"
(grep "misc/Class-Registry-3.0.tar.gz" "$tempdir/modules.txt" > /dev/null \
    && echo "ok 9") || echo "not ok 9"

perl $pmbp --root-dir-name="$tempdir" \
    --read-module-index "$tempdir/modules.txt" \
    --select-module Class::Registry~3.0=http://wakaba.github.com/packages/perl/Class-Registry-3.0.tar.gz \
    --write-pmb-install-list "$tempdir/pmb-modules.txt"

(grep "Class::Registry~3.0" "$tempdir/pmb-modules.txt" > /dev/null \
    && echo "ok 10") || echo "not ok 10"
(grep "Class::Registry" "$tempdir/pmb-modules.txt" > /dev/null \
    && echo "ok 11") || echo "not ok 11"

rm -fr $tempdir
