#!/bin/sh
echo "1..6"
basedir=$(cd `dirname $0`/../.. && pwd)
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p $tempdir/git1
cd $tempdir/git1 && git init && touch a && git add a && git commit -m new

# Test case 1 : new Git module should be installed into specified container directory

mkdir -p $tempdir/foo
cd $tempdir/foo && git init

(perl $pmbp --root-dir-name $tempdir/foo --add-git-submodule "t_deps/modules $tempdir/git1" && echo "ok 1") || echo "not ok 1"
([ -f "$tempdir/foo/t_deps/modules/git1/a" ] && echo "ok 2") || echo "not ok 2"

rm -fr $tempdir/foo

# Test case 2 : in case that specified Git module is already installed in "modules" directory,
#   new Git module shouldn't be installed in specified container directory

mkdir -p $tempdir/foo
cd $tempdir/foo && git init

(perl $pmbp --root-dir-name $tempdir/foo --add-git-submodule $tempdir/git1 && echo "ok 3") || echo "not ok 3"
(perl $pmbp --root-dir-name $tempdir/foo --add-git-submodule "t_deps/modules $tempdir/git1" && echo "ok 4") || echo "not ok 4"
([ -f "$tempdir/foo/modules/git1/a" ] && echo "ok 5") || echo "not ok 5"
([ ! -d "$tempdir/foo/t_deps" ] && echo "ok 6") || echo "not ok 6"

rm -fr $tempdir/foo

rm -fr $tempdir

# * LICENSE
#
# Copyright 2012-2016 Wakaba <wakaba@suikawiki.org>.
# Copyright 2017 Hatena <https://www.hatena.ne.jp/company/>.
#
# This library is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself.
