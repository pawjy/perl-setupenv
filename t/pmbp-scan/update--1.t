#!/bin/sh
echo "1..13"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p "$tempdir/config/perl"
echo "Test::Class" > "$tempdir/config/perl/modules.txt"

perl $pmbp --root-dir-name "$tempdir" \
    --update

(ls $tempdir/local/perl-*/pm/lib/perl5/Test/Class.pm > /dev/null && echo "not ok 1") || echo "ok 1"
(ls $tempdir/deps/pmpp/lib/perl5/Test/Class.pm > /dev/null && echo "ok 2") || echo "ok 2"

(grep Test::Class $tempdir/deps/pmtar/modules/index.txt > /dev/null && echo "ok 3") || echo "not ok 3"
(grep Test::Class $tempdir/config/perl/pmb-install.txt > /dev/null && echo "ok 4") || echo "not ok 4"

(ls $tempdir/deps/pmtar/.git/config > /dev/null && echo "ok 5") || echo "not ok 5"
(ls $tempdir/deps/pmpp/.git/config > /dev/null && echo "ok 6") || echo "not ok 6"

perl $pmbp --root-dir-name "$tempdir" --install

(ls "$tempdir/config/perl/libs.txt" > /dev/null && echo "ok 7") || echo "not ok 7"
perl -e "-f '$tempdir/config/perl/libs.txt' ? print qq{ok 8\n} : print qq{not ok 8\n}"

(PERL5LIB="`cat \"$tempdir/config/perl/libs.txt\"`" \
    perl -e 'use Test::Class' && echo "ok 9") || echo "not ok 9"

(ls $tempdir/local/perl-*/pm/lib/perl5/Test/Class.pm > /dev/null && echo "ok 10") || echo "not ok 10"
(ls $tempdir/deps/pmpp/lib/perl5/Test/Class.pm > /dev/null && echo "ok 11") || echo "ok 11"

perl $pmbp --root-dir-name "$tempdir" --update
perl $pmbp --root-dir-name "$tempdir" --install
perl $pmbp --root-dir-name "$tempdir" --update --install

(ls $tempdir/local/perl-*/pm/lib/perl5/Test/Class.pm > /dev/null && echo "ok 12") || echo "not ok 12"
(ls $tempdir/deps/pmpp/lib/perl5/Test/Class.pm > /dev/null && echo "ok 13") || echo "ok 13"

rm -fr $tempdir
