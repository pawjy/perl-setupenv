use strict;
use warnings;
use File::Temp qw(tempdir);
use Cwd qw(abs_path);

my $DEBUG = 0;

print "1..5\n";

my $pmbp = __FILE__;
$pmbp =~ s{[^/\\]+$}{};
$pmbp ||= '.';
$pmbp .= '/../../bin/pmbp.pl';
my $tempdir = tempdir ('PMBP-TEST-XX'.'XX'.'XX', TMPDIR => 1, CLEANUP => !$DEBUG);

my $conf_file_name = abs_path "$tempdir/httpd.conf";
my $port = 1024 + int rand 10000;

my $root_dir_name = $tempdir;
my $httpd = "$root_dir_name/local/apache/httpd-2.2/bin/httpd";

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
close $conf_file;

my $start_log_file_name = "$root_dir_name/local/apache/httpd-2.2/logs/start_error_log";
system $httpd, '-f', $conf_file_name, '-k', 'start', '-E', $start_log_file_name;

sleep 4;

system "cat", $start_log_file_name;

# XXX

my $log_file_name = "$root_dir_name/local/apache/httpd-2.2/logs/error_log";
system "cat", $log_file_name;

system "ls", "$root_dir_name/local/apache/httpd-2.2/logs";

system $httpd, '-f', $conf_file_name, '-t', '-E', $start_log_file_name;

# XXX

print "ok 1\n";

if (`curl http://localhost:$port/` eq 'PASS') {
  print "ok 2\n";
} else {
  print "not ok 2\n";
}

system $httpd, '-f', $conf_file_name, '-k', 'stop';

sleep 2;

print "ok 3\n";

(system 'perl', $pmbp, '--root-dir-name' => $root_dir_name,
     '--install-module=Apache::Cookie') == 0
    or die "Can't install perl and mod_perl1 and libapreq";

my $conf1_file_name = "$root_dir_name/local/apache/httpd-1.3/conf/httpd.conf";
open my $conf1_file, '>', $conf1_file_name or die "$0: $conf1_file_name: $!";
printf $conf1_file q{
ServerName Hoge
Listen %d

LoadModule perl_module libexec/libperl.so
AddModule mod_perl.c

<Perl>
  use lib qw(%s);

  package MyHandler;
  use Apache::Constants qw(:common);
  use Apache::Request;
  
  sub handler {
    my $r = shift;
    my $apr = Apache::Request->new ($r);
    my $status = $apr->parse;
    if ($status == OK) {
      $r->send_http_header ('text/plain');
      $r->print ('PASS');
      return OK;
    }
  }
</Perl>

<Location />
  SetHandler perl-script
  PerlSendHeader on
  PerlHandler MyHandler
</Location>
},
    ++$port,
    join ':', @lib;
close $conf1_file;

my $apachectl = "$root_dir_name/local/apache/httpd-1.3/bin/apachectl";

{
  local $ENV{PERL5LIB} = join ':', @lib;
  system $apachectl, 'start';
}
sleep 2;

if (`curl http://localhost:$port/` eq 'PASS') {
  print "ok 4\n";
} else {
  print "not ok 4\n";
}

system $apachectl, 'stop';
sleep 2;

print "ok 5\n";
