#!/bin/sh
echo "1..5"
basedir=$(cd `dirname $0`/../.. && pwd)
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p $tempdir/foo
cd $tempdir/foo && git init

mkdir -p $tempdir/git1
cd $tempdir/git1 && git init && mkdir -p config/perl && perl -e 'print "\nhoge\n#abc\nfoo bar\nfuga"' > config/perl/pmbp-extra-modules.txt && git add config && git commit -m new

mkdir -p $tempdir/git2
cd $tempdir/git2 && git init && mkdir -p config/perl && perl -e 'print "abc"' > config/perl/pmbp-extra-modules.txt && git add config && git commit -m new

mkdir -p $tempdir/hoge/git1
cd $tempdir/hoge/git1 && git init && touch b && git add b && git commit -m new

(perl $pmbp --root-dir-name $tempdir/foo --add-git-submodule $tempdir/git1 && echo "ok 1") || echo "not ok 1"
(perl $pmbp --root-dir-name $tempdir/foo --add-git-submodule $tempdir/git1 && echo "ok 2") || echo "not ok 2"

perl -e 'print qq{\n- "../../modules/git1" hoge fuga}' > $tempdir/a.txt
(diff -u $tempdir/a.txt $tempdir/foo/config/perl/pmbp-exclusions.txt && echo "ok 3") || echo "not ok 3"

(perl $pmbp --root-dir-name $tempdir/foo --add-git-submodule $tempdir/git2 && echo "ok 4") || echo "not ok 4"

perl -e 'print qq{\n- "../../modules/git1" hoge fuga\n- "../../modules/git2" abc}' > $tempdir/b.txt
(diff -u $tempdir/b.txt $tempdir/foo/config/perl/pmbp-exclusions.txt && echo "ok 5") || echo "not ok 5"

rm -fr $tempdir
