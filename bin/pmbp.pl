use strict;
use warnings;
use Config;
use Cwd qw(abs_path);
use File::Path qw(make_path remove_tree);
use File::Copy qw(copy);
use Getopt::Long;

my $perl = 'perl';
my $perl_version;
my $wget = 'wget';
my $cpanm_url = q<http://cpanmin.us>;
my $root_dir_name = '.';
my @command;
my @cpanm_options = qw(--notest);

GetOptions (
  '--perl-command=s' => \$perl,
  '--wget-command=s' => \$wget,
  '--cpanm-url=s' => \$cpanm_url,
  '--root-dir-name=s' => \$root_dir_name,
  '--perl-version=s' => \$perl_version,
  '--install-module=s' => sub {
    push @command, {type => 'install-module', module => $_[1]};
  },
  '--print-libs' => sub {
    push @command, {type => 'print-libs'};
  },
) or die "Usage: $0 options... (See source for details)\n";

$perl_version ||= `@{[quotemeta $perl]} -e 'print \$^V'`;
$perl_version =~ s/^v//;

$root_dir_name = abs_path $root_dir_name;
my $local_dir_name = $root_dir_name . '/local/perl-' . $perl_version;
my $pmb_dir_name = $local_dir_name . '/pmbp';
my $temp_dir_name = $pmb_dir_name . '/tmp';
my $cpanm_dir_name = $temp_dir_name . '/cpanm';
my $cpanm_home_dir_name = $cpanm_dir_name . '/tmp';
my $cpanm = $cpanm_dir_name . '/bin/cpanm';
my $cpanm_lib_dir_name = $cpanm_dir_name . '/lib/perl5';
my $installed_dir_name = $local_dir_name . '/pm';
my $log_dir_name = $temp_dir_name . '/logs';

sub info ($) {
  print $_[0], $_[0] =~ /\n\z/ ? "" : "\n";
} # info

sub mkdir_for_file ($) {
  my $file_name = $_[0];
  $file_name =~ s{[^/\\]+$}{};
  make_path $file_name;
} # mkdir_for_file

sub copy_log_file ($$) {
  my ($file_name, $module_name) = @_;
  my $log_file_name = $module_name;
  $log_file_name =~ s/::/-/;
  $log_file_name = "$log_dir_name/@{[time]}-$log_file_name.log";
  mkdir_for_file $log_file_name;
  copy $file_name => $log_file_name or die "Can't save log file: $!\n";
  info "Log file: $log_file_name";
  open my $file, '<', $file_name or die "$0: $file_name: $!";
  local $/ = undef;
  return <$file>;
} # copy_log_file

sub save_url ($$) {
  system 'wget', '-O', $_[1], $_[0];
  die "Failed to download <$_[0]>\n" unless -f $_[1];
} # save_url

sub prepare_cpanm () {
  return if -f $cpanm;
  mkdir_for_file $cpanm;
  save_url $cpanm_url => $cpanm;
} # prepare_cpanm

sub cpanm ($$);
our $CPANMDepth = 0;
sub cpanm ($$) {
  my ($args, $modules) = @_;
  prepare_cpanm;

  my $perl_lib_dir_name = $args->{perl_lib_dir_name}
      or die "No |perl_lib_dir_name| specified";

  my $redo = 0;
  COMMAND: {
    my @required_cpanm;
    my @required_install;
    my @required_install2;

    local $ENV{LANG} = 'C';
    local $ENV{PERL_CPANM_HOME} = $cpanm_home_dir_name;
    my @cmd = ($perl, '-I' . $cpanm_lib_dir_name, $cpanm,
               $args->{local_option} || '-L' => $perl_lib_dir_name,
               @cpanm_options,
               keys %$modules);
    info join ' ', 'PERL_CPANM_HOME=' . $cpanm_home_dir_name, @cmd;
    open my $cmd, '-|', ((join ' ', map { quotemeta } @cmd) . ' 2>&1')
        or die "Failed to execute @cmd - $!\n";
    my $current_module_name = '';
    while (<$cmd>) {
      info "cpanm($CPANMDepth/$redo): $_";
      
      if (/^Can\'t locate (\S+)\.pm in \@INC/) {
        my $module = $1;
        $module =~ s{/}{::}g;
        push @required_cpanm, $module;
      } elsif (/^--> Working on (\S)+$/) {
        $current_module_name = $1;
      } elsif (/^! Installing (\S+) failed\. See (.+?) for details\.$/) {
        my $log = copy_log_file $2 => $1;
        if ($log =~ m{^make: .+?ExtUtils/xsubpp}m or
            $log =~ m{^Can\'t open perl script "ExtUtils/xsubpp"}m) {
          push @required_install, qw{ExtUtils::MakeMaker ExtUtils::ParseXS};
        }
      }
    }
    close $cmd or do {
      unless ($CPANMDepth > 100 or $redo++ > 10) {
        if (@required_cpanm and $perl_lib_dir_name ne $cpanm_dir_name) {
          local $CPANMDepth = $CPANMDepth + 1;
          for my $module (@required_cpanm) {
            cpanm {perl_lib_dir_name => $cpanm_dir_name, local_option => '-l'},
                { $module => '' };
          }
          redo COMMAND;
        } elsif (@required_install and $perl_lib_dir_name ne $cpanm_dir_name) {
          local $CPANMDepth = $CPANMDepth + 1;
          for my $module (@required_install) {
            cpanm {perl_lib_dir_name => $installed_dir_name},
                { $module => '' };
          }
          redo COMMAND;
        }
      }
      if ($args->{ignore_errors}) {
        info "cpanm($CPANMDepth): Installing @{[join ' ', keys %$modules]} failed (@{[$? >> 8]}) (Ignored)";
      } else {
        die "cpanm($CPANMDepth): Installing @{[join ' ', keys %$modules]} failed (@{[$? >> 8]})\n";
      }
    };
  } # COMMAND
} # cpanm

sub destroy_cpanm_home () {
  remove_tree $cpanm_home_dir_name;
} # destroy_cpanm_home

sub destroy () {
  destroy_cpanm_home;
} # destroy

for my $command (@command) {
  if ($command->{type} eq 'install-module') {
    info "Install $command->{module}...";
    cpanm {perl_lib_dir_name => $installed_dir_name},
        {$command->{module} => ''};
  } elsif ($command->{type} eq 'print-libs') {
    my @lib = grep { defined } map { abs_path $_ } map { glob $_ }
      qq{$root_dir_name/lib},
      qq{$root_dir_name/modules/*/lib},
      qq{$root_dir_name/local/submodules/*/lib},
      qq{$installed_dir_name/lib/perl5/$Config{archname}},
      qq{$installed_dir_name/lib/perl5};
    print join ':', @lib;
  } else {
    die "Command |$command->{type}| is not defined";
  }
}

destroy;

=head1 LICENSE

Copyright 2012 Wakaba <w@suika.fam.cx>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
