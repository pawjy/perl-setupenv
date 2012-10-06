#!/bin/sh
echo "1..5"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

export PMBP_NO_PERL_INSTALL=$TRAVIS

mkdir -p "$tempdir/config/perl"
echo 5.14.0 > "$tempdir/config/perl/version.txt"
echo "Test::Class" > "$tempdir/config/perl/modules.txt"

perl $pmbp --root-dir-name "$tempdir" \
    --install

(ls "$tempdir/config/perl/libs.txt" > /dev/null && echo "ok 1") || echo "not ok 1"
perl -e "-f '$tempdir/config/perl/libs.txt' ? print qq{ok 2\n} : print qq{not ok 2\n}"

(PERL5LIB="`cat \"$tempdir/config/perl/libs.txt\"`" \
    perl -e 'use Test::Class' && echo "ok 3") || echo "not ok 3"
(PERL5LIB="`cat \"$tempdir/config/perl/libs.txt\"`" \
    perl -e '$^V eq "5.14.0" ? print "ok 4\n" : print "not ok 4\n"') || echo "not ok 4"

(ls $tempdir/local/perl-5.14.0/pm/lib/perl5/Test/Class.pm > /dev/null && echo "ok 5") || echo "not ok 5"

rm -fr $tempdir
