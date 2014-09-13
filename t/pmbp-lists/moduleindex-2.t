#!/bin/sh
echo "1..5"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp
packstxt=$tempdir/list.txt

perl $pmbp --root-dir-name="$tempdir" \
    --read-module-index="$packstxt" \
    --scandeps CGI::Carp \
    --select-module Class::Registry~3.0=http://wakaba.github.com/packages/perl/Class-Registry-3.0.tar.gz \
    --write-module-index="$packstxt"

perl $pmbp --root-dir-name="$tempdir" \
    --set-module-index "$packstxt" \
    --install-module CGI::Carp \
    --install-module Class::Registry \
    --write-libs-txt "$tempdir/libs.txt"

(PERL5LIB="`cat $tempdir/libs.txt`" \
    perl -MCGI::Carp -MClass::Registry \
         -e 'die unless $CGI::Carp::VERSION and $Class::Registry::VERSION eq "3.0"' \
    && echo "ok 1") || echo "not ok 1"

(ls $tempdir/deps/pmtar/authors/id/misc/Class-Registry-3.0.tar.gz > /dev/null && echo "ok 2" ) || echo "not ok 2"
(ls $tempdir/deps/pmtar/authors/id/Class-Registry-3.0.tar.gz > /dev/null && echo "not ok 3" ) || echo "ok 3"
(ls $tempdir/deps/pmtar/authors/id/*/*/*/CGI-*.tar.gz > /dev/null && echo "ok 4" ) || echo "not ok 4"

tempdir2=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

perl $pmbp --root-dir-name="$tempdir2" \
    --read-module-index="$packstxt" \
    --install-module CGI::Carp \
    --install-module Class::Registry~3.0=http://wakaba.github.com/packages/perl/Class-Registry-3.0.tar.gz \
    --write-libs-txt "$tempdir2/libs.txt"

(PERL5LIB="`cat $tempdir2/libs.txt`" \
    perl -MCGI::Carp -MClass::Registry \
         -e 'die unless $CGI::Carp::VERSION and $Class::Registry::VERSION eq "3.0"' \
    && echo "ok 5") || echo "not ok 5"

rm -fr $tempdir $tempdir2
