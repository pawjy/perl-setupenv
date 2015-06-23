#!/bin/sh
echo "1..4"
basedir=$(cd `dirname $0`/../.. && pwd)
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p $tempdir/foo
cd $tempdir/foo && git init

mkdir -p $tempdir/git1
cd $tempdir/git1 && git init && touch a && git add a && git commit -m new

mkdir -p $tempdir/git2
cd $tempdir/git2 && git init && touch b && git add b && git submodule add $tempdir/git1 modules/git1 && git commit -m new

(perl $pmbp --root-dir-name $tempdir/foo --add-git-submodule-recursively $tempdir/git2 && echo "ok 1") || echo "not ok 1"
(cat $tempdir/foo/modules/git1/a && echo "ok 2") || echo "not ok 2"

mkdir -p $tempdir/git3
cd $tempdir/git3 && git init && touch c && git add c && git commit -m new

cd $tempdir/git2 && git submodule add $tempdir/git3 modules/git3 && git commit -m new

cd $tempdir/foo/modules/git2 && git pull
(perl $pmbp --root-dir-name $tempdir/foo --add-git-submodule-recursively $tempdir/git2 && echo "ok 3") || echo "not ok 3"
(cat $tempdir/foo/modules/git3/c && echo "ok 4") || echo "not ok 4"

rm -fr $tempdir
