#!/bin/sh
echo "1..2"
basedir=`dirname $0`/../..
pmbp=$basedir/bin/pmbp.pl
tempdir=`perl -MFile::Temp=tempdir -e 'print tempdir'`/testapp

mkdir -p "$tempdir/deps/pmpp/bin"

echo "#!/bin/perl
use Path::Class;
print \$Path::Class::VERSION" > "$tempdir/deps/pmpp/bin/hogehoge"
chmod u+x "$tempdir/deps/pmpp/bin/hogehoge"

perl $pmbp --root-dir-name "$tempdir" \
    --install \
    --create-perl-command-shortcut hogehoge && echo "ok 1"

$tempdir/hogehoge > "$tempdir/result1"

perl $pmbp --root-dir-name \"$tempdir\" --print-libs > "$tempdir/libs.txt"

PERL5LIB=`cat $tempdir/libs.txt` \
perl -MPath::Class -e "(\$Path::Class::VERSION && <> eq \$Path::Class::VERSION) ? print qq{ok 2\n} : print qq{not ok 2\n}" "$tempdir/result1"

rm -fr $tempdir
