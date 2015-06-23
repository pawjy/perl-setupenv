#!/bin/sh
echo "1..9"
basedir=$(cd `dirname $0`/../.. && pwd)
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p $tempdir/foo
cd $tempdir/foo && git init

mkdir -p $tempdir/git1
cd $tempdir/git1 && git init && touch a && git add a && git commit -m new

mkdir -p $tempdir/hoge/git1
cd $tempdir/hoge/git1 && git init && touch b && git add b && git commit -m new

(perl $pmbp --root-dir-name $tempdir/foo --add-git-submodule $tempdir/git1 && echo "ok 1") || echo "not ok 1"
(perl $pmbp --root-dir-name $tempdir/foo --add-git-submodule $tempdir/git1 && echo "ok 2") || echo "not ok 2"

(cat $tempdir/foo/modules/git1/a && echo "ok 3") || echo "not ok 3"
(ls $tempdir/foo/modules/git1.2 && echo "not ok 4") || echo "ok 4"

(perl $pmbp --root-dir-name $tempdir/foo --add-git-submodule $tempdir/hoge/git1 && echo "ok 5") || echo "not ok 5"
(cat $tempdir/foo/modules/git1/b && echo "not ok 6") || echo "ok 6"
(cat $tempdir/foo/modules/git1.2/b && echo "ok 7") || echo "not ok 7"

(perl $pmbp --root-dir-name $tempdir/foo --add-git-submodule aa/m\ $tempdir/git1 && echo "ok 8") || echo "not ok 8"
(cat $tempdir/foo/aa/m/git1/a && echo "ok 9") || echo "not ok 9"

rm -fr $tempdir
