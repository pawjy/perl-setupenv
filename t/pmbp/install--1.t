#!/bin/sh
echo "1..7"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p "$tempdir/config/perl"
echo "Test::Class" > "$tempdir/config/perl/modules.txt"

perl $pmbp --root-dir-name "$tempdir" \
    --install

(ls "$tempdir/config/perl/libs.txt" > /dev/null && echo "ok 1") || echo "not ok 1"
perl -e "-f '$tempdir/config/perl/libs.txt' ? print qq{ok 2\n} : print qq{not ok 2\n}"

(PERL5LIB="`cat \"$tempdir/config/perl/libs.txt\"`" \
    perl -e 'use Test::Class' && echo "ok 3") || echo "not ok 3"

(ls $tempdir/local/perl-*/pm/lib/perl5/Test/Class.pm > /dev/null && echo "ok 4") || echo "not ok 4"
(ls $tempdir/deps/pmpp/lib/perl5/Test/Class.pm > /dev/null && echo "not ok 5") || echo "ok 5"

(ls $tempdir/deps/pmpp/.git/config > /dev/null && echo "ok 6") || echo "not ok 6"
(ls $tempdir/deps/pmtar/.git/config > /dev/null && echo "ok 7") || echo "not ok 7"

rm -fr $tempdir
