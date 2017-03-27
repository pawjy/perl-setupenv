#!/bin/sh
echo "1..16"
basedir=$(cd `dirname $0`/../.. && pwd)
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p $tempdir/git1
cd $tempdir/git1 && git init && touch a && git add a && git commit -m new

mkdir -p $tempdir/git2
cd $tempdir/git2 && git init && touch b && git add b && git submodule add $tempdir/git1 modules/git1 && git commit -m new

# Test case 1 : new Git module should be installed into specified container directory

mkdir -p $tempdir/foo
cd $tempdir/foo && git init

(perl $pmbp --root-dir-name $tempdir/foo --add-git-submodule-recursively "t_deps/modules $tempdir/git2" && echo "ok 1") || echo "not ok 1"
([ -f "$tempdir/foo/t_deps/modules/git1/a" ] && echo "ok 2") || echo "not ok 2"
([ -f "$tempdir/foo/t_deps/modules/git2/b" ] && echo "ok 3") || echo "not ok 3"

rm -fr $tempdir/foo

# Test case 2 : in case that specified Git module is already installed in "modules" directory,
#   new Git module shouldn't be installed in specified container directory

mkdir -p $tempdir/foo
cd $tempdir/foo && git init

(perl $pmbp --root-dir-name $tempdir/foo --add-git-submodule-recursively $tempdir/git2 && echo "ok 4") || echo "not ok 4"
(perl $pmbp --root-dir-name $tempdir/foo --add-git-submodule-recursively "t_deps/modules $tempdir/git2" && echo "ok 5") || echo "not ok 5"
([ -f "$tempdir/foo/modules/git1/a" ] && echo "ok 6") || echo "not ok 6"
([ -f "$tempdir/foo/modules/git2/b" ] && echo "ok 7") || echo "not ok 7"
([ ! -d "$tempdir/foo/t_deps" ] && echo "ok 8") || echo "not ok 8"

rm -fr $tempdir/foo

# Test case 3 : in case that submodule of specified Git module is already installed in "modules" directory,
#   new Git module should be installed in specified container directory but its submodule shouldn't

mkdir -p $tempdir/foo
cd $tempdir/foo && git init

(perl $pmbp --root-dir-name $tempdir/foo --add-git-submodule-recursively $tempdir/git1 && echo "ok 9") || echo "not ok 9"
(perl $pmbp --root-dir-name $tempdir/foo --add-git-submodule-recursively "t_deps/modules $tempdir/git2" && echo "ok 10") || echo "not ok 10"
([ -f "$tempdir/foo/modules/git1/a" ] && echo "ok 11") || echo "not ok 11"
([ -f "$tempdir/foo/t_deps/modules/git2/b" ] && echo "ok 12") || echo "not ok 12"
([ ! -d "$tempdir/foo/t_deps/modules/git1" ] && echo "ok 13") || echo "not ok 13"

rm -fr $tempdir/foo

# Test case 4 : after new submodule is added into installed submodule,
#   `--add-git-submodule-recursively` should install newly added submodule

mkdir -p $tempdir/foo
cd $tempdir/foo && git init

(perl $pmbp --root-dir-name $tempdir/foo --add-git-submodule-recursively "t_deps/modules $tempdir/git2" && echo "ok 14") || echo "not ok 14"

mkdir -p $tempdir/git3
cd $tempdir/git3 && git init && touch c && git add c && git commit -m new

cd $tempdir/git2 && git submodule add $tempdir/git3 modules/git3 && git commit -m new

cd $tempdir/foo/t_deps/modules/git2 && git pull
(perl $pmbp --root-dir-name $tempdir/foo --add-git-submodule-recursively "t_deps/modules $tempdir/git2" && echo "ok 15") || echo "not ok 15"
([ -f "$tempdir/foo/t_deps/modules/git3/c" ] && echo "ok 16") || echo "not ok 16"

rm -fr $tempdir/foo

rm -fr $tempdir

# * LICENSE
#
# Copyright 2012-2016 Wakaba <wakaba@suikawiki.org>.
# Copyright 2017 Hatena <https://www.hatena.ne.jp/company/>.
#
# This library is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself.
