#!/bin/sh
echo "1..8"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p "$tempdir/deps/pmpp/bin/fuga"

echo "#!/usr/bin/perl
hoge" > "$tempdir/deps/pmpp/bin/script1"
echo "#!/usr/local/bin/perl -w
hoge" > "$tempdir/deps/pmpp/bin/script2"
echo "#!/usr/bin/env perl -Ihoge
hoge" > "$tempdir/deps/pmpp/bin/script3"
echo "#!C:/hoge/fuga/perl
hoge" > "$tempdir/deps/pmpp/bin/script4"
echo "#!perl
print \"ok 8\", chr 0x0A" > "$tempdir/deps/pmpp/bin/script5"
echo "#!/usr/bin/perl5.10.1
hoge" > "$tempdir/deps/pmpp/bin/fuga/script6"
echo "#!/hoge/foo/local/perl/bin/perl
hoge" > "$tempdir/deps/pmpp/bin/script7"
chmod u+x $tempdir/deps/pmpp/bin/*

perl $pmbp --root-dir-name "$tempdir" --install

perl -e 'local $/ = undef; (<> =~ m{^#!\S+/perl\nhoge$} && print "ok 1\n") || print "not ok 1\n"' < `ls $tempdir/local/perl-*/pm/bin/script1 | head -1`
perl -e 'local $/ = undef; (<> =~ m{^#!\S+/perl -w\nhoge$} && print "ok 2\n") || print "not ok 2\n"' < `ls $tempdir/local/perl-*/pm/bin/script2 | head -1`
perl -e 'local $/ = undef; (<> =~ m{^#!\S+/perl -Ihoge\nhoge$} && print "ok 3\n") || print "not ok 3\n"' < `ls $tempdir/local/perl-*/pm/bin/script3 | head -1`
perl -e 'local $/ = undef; (<> =~ m{^#!\S+/perl\nhoge$} && print "ok 4\n") || print "not ok 4\n"' < `ls $tempdir/local/perl-*/pm/bin/script4 | head -1`
perl -e 'local $/ = undef; (<> =~ m{^#!\S+/perl\nprint .+$} && print "ok 5\n") || print "not ok 5\n"' < `ls $tempdir/local/perl-*/pm/bin/script5 | head -1`
perl -e 'local $/ = undef; (<> =~ m{^#!\S+/perl\nhoge$} && print "ok 6\n") || print "not ok 6\n"' < `ls $tempdir/local/perl-*/pm/bin/fuga/script6 | head -1`
perl -e 'local $/ = undef; (<> =~ m{^#!\S+/perl\nhoge$} && print "ok 7\n") || print "not ok 7\n"' < `ls $tempdir/local/perl-*/pm/bin/script7 | head -1`

# 8
`ls $tempdir/local/perl-*/pm/bin/script5`

rm -fr $tempdir
