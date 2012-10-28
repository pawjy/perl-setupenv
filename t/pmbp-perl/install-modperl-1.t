use strict;
use warnings;
use File::Temp qw(tempdir);
use Cwd qw(abs_path);

print "1..3\n";

my $pmbp = __FILE__;
$pmbp =~ s{[^/\\]+$}{};
$pmbp ||= '.';
$pmbp .= '/../../bin/pmbp.pl';
my $tempdir = tempdir ('PMBP-TEST-XX'.'XX'.'XX', TMPDIR => 1, CLEANUP => 1);

my $conf_file_name = abs_path "$tempdir/httpd.conf";
my $port = 1024 + int rand 10000;

my $httpd = "$root_dir_name/local/apache/httpd-2.2/bin/httpd";
my $root_dir_name = $tempdir;

(system 'perl', $pmbp, '--root-dir-name' => $root_dir_name,
     '--install-perl',
     '--install-module=mod_perl2') == 0
    or die "Can't install perl and mod_perl2";

my @lib = split /:/, `perl $pmbp --print-libs --root-dir-name $root_dir_name`;

open my $conf_file, '>', $conf_file_name or die "$0: $conf_file_name: $!";
printf $conf_file q{
LoadModule perl_module modules/mod_perl.so
ServerName Hoge
Listen %d

%s

<Perl>
  package MyHandler;
  use Apache2::RequestRec ();
  use Apache2::RequestIO ();
  use Apache2::Const -compile => ':common';
  
  sub handler {
    my $r = shift;
    
    $r->content_type ('text/plain');
    print "PASS";
    
    return Apache2::Const::OK;
  }
</Perl>

<Location />

SetHandler perl-script
PerlResponseHandler MyHandler

</Location>

},
    $port,
    (join "\n", map { "PerlSwitches -I$_" } @lib);

(system $httpd, '-f', $conf_file_name, '-k', 'start') == 0
    or die "Can't start apache";

sleep 2;

print "ok 1\n";

if (`curl http://localhost:$port/` eq 'PASS') {
  print "ok 2\n";
} else {
  print "not ok 2\n";
}

(system $httpd, '-f', $conf_file_name, '-k', 'stop') == 0
    or die "Can't stop apache";

sleep 2;

print "ok 3\n";
