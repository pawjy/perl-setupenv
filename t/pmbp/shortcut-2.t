#!/bin/bash
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

PERL5LIB="`perl $pmbp --root-dir-name \"$tempdir\" --print-libs`" \
perl -MPath::Class -e "(\$Path::Class::VERSION && `$tempdir/hogehoge` eq \$Path::Class::VERSION) ? print qq{ok 2\n} : print qq{not ok 2\n}"

rm -fr $tempdir
