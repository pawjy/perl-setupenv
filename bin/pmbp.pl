use strict;
use warnings;
use Config;
use Cwd qw(abs_path);
use File::Path qw(make_path remove_tree);
use File::Copy qw(copy move);
use File::Temp ();
use File::Spec ();
use Getopt::Long;

my $perl = 'perl';
my $perl_version;
my $wget = 'wget';
my $cpanm_url = q<http://cpanmin.us>;
my $root_dir_name = '.';
my $dists_dir_name;
my @command;
my @cpanm_option = qw(--notest --cascade-search);
my $cpan_index_url = q<http://search.cpan.org/CPAN/modules/02packages.details.txt.gz>;
my @cpan_mirror = qw(
  http://search.cpan.org/CPAN
  http://cpan.metacpan.org/
  http://backpan.perl.org/
);

GetOptions (
  '--perl-command=s' => \$perl,
  '--wget-command=s' => \$wget,
  '--cpanm-url=s' => \$cpanm_url,
  '--cpan-index-url=s' => \$cpan_index_url,
  '--cpanm-verbose' => sub { push @cpanm_option, '--verbose' },
  '--root-dir-name=s' => \$root_dir_name,
  '--dists-dir-name=s' => \$dists_dir_name,
  '--perl-version=s' => \$perl_version,

  '--install-module=s' => sub {
    push @command, {type => 'install-module', module => $_[1]};
  },
  '--scandeps=s' => sub {
    push @command, {type => 'scandeps', module => $_[1]};
  },
  '--read-package-list=s' => sub {
    push @command, {type => 'read-package-list', file_name => $_[1]};
  },
  '--write-package-list=s' => sub {
    push @command, {type => 'write-package-list', file_name => $_[1]};
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
$dists_dir_name ||= $temp_dir_name . '/pmtar';
push @cpanm_option, '--save-dists' => $dists_dir_name;
if (-d $dists_dir_name) {
  push @cpanm_option, '--mirror' => abs_path $dists_dir_name;
}
my $packages_details_file_name = $dists_dir_name . '/modules/02packages.details.txt';
my $install_json_dir_name = $dists_dir_name . '/meta';
my $deps_json_dir_name = $dists_dir_name . '/deps';
push @cpanm_option, map { ('--mirror' => $_) } @cpan_mirror;
my $PackageList = [];

sub install_modules ($);
sub install_support_modules ($);
sub scandeps ($;%);

sub info ($) {
  print STDERR $_[0], $_[0] =~ /\n\z/ ? "" : "\n";
} # info

sub info_writing ($$) {
  print STDERR "Writing ", $_[0], " ", File::Spec->abs2rel ($_[1]), "...\n";
} # info_writing

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

sub save_url ($$$) {
  system "wget -O @{[quotemeta qq{$_[1]/$_[2]}]} @{[quotemeta $_[0]]} 1>&2";
  die "Failed to download <$_[0]>\n" unless -f $_[1] . '/' . $_[2];
} # save_url

{
  my $json_installed;
  
  sub encode_json ($) {
    unless ($json_installed) {
      $json_installed = 1;
      install_support_modules {'JSON' => ''};
    }
    require JSON;
    return JSON->new->utf8->allow_blessed->convert_blessed->allow_nonref->pretty->canonical->encode ($_[0]);
  } # encode_json

  sub decode_json ($) {
    unless ($json_installed) {
      $json_installed = 1;
      install_support_modules {'JSON' => ''};
    }
    require JSON;
    return JSON->new->utf8->allow_blessed->convert_blessed->allow_nonref->pretty->canonical->decode ($_[0]);
  } # decode_json
}

sub prepare_cpanm () {
  return if -f $cpanm;
  mkdir_for_file $cpanm;
  save_url $cpanm_url => $cpanm_dir_name . '/bin', 'cpanm';
} # prepare_cpanm

our $CPANMDepth = 0;
my $cpanm_init = 0;
sub cpanm ($$) {
  my ($args, $modules) = @_;
  my $result = {};
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
               ($args->{skip_satisfied} ? '--skip-satisfied' : ()),
#XXX               '--mirror-index' => $packages_details_file_name . '.gz',
               @cpanm_option,
               ($args->{scandeps} ? ('--scandeps', '--format=json') : ()),
               keys %$modules);
    info join ' ', 'PERL_CPANM_HOME=' . $cpanm_home_dir_name, @cmd;
    my $json_temp_file = File::Temp->new;
    open my $cmd, '-|', ((join ' ', map { quotemeta } @cmd) .
                         ' 2>&1 ' .
                         ($args->{scandeps} ? ' > ' . quotemeta $json_temp_file : '') .
                         '')
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
            install_support_modules {$module => ''};
          }
          redo COMMAND;
        } elsif (@required_install and $perl_lib_dir_name ne $cpanm_dir_name) {
          local $CPANMDepth = $CPANMDepth + 1;
          for my $module (@required_install) {
            if ($args->{scandeps}) {
              my $r = scandeps {$module => ''};
              # XXX merge $r->{output_json} with parent's output_json...
            } else {
              install_modules {$module => ''};
            }
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
    if ($args->{scandeps} and -f $json_temp_file->filename) {
      open my $file, '<', $json_temp_file->filename
          or die "$0: @{[$json_temp_file->filename]}: $!";
      local $/ = undef;
      $result->{output_json} = decode_json (<$file>);
    }
  } # COMMAND
  return $result;
} # cpanm

sub install_modules ($) {
  cpanm {perl_lib_dir_name => $installed_dir_name}, $_[0];
} # install_modules

sub install_support_modules ($) {
  cpanm {perl_lib_dir_name => $cpanm_dir_name,
         local_option => '-l', skip_satisfied => 1}, $_[0];
} # install_support_modules

sub scandeps ($;%) {
  my ($modules, %args) = @_;

  if ($args{skip_if_found} and 1 == keys %$modules) {
    for (@$PackageList) {
      if (defined $modules->{$_->{name}}) {
        my $path = $_->{path};
        $path =~ s{^.+/}{};
        $path =~ s{\.tar\.gz$}{};
        my $json_file_name = "$deps_json_dir_name/$path.json";
        return if -f $json_file_name;
      }
    }
  }

  my $temp_dir = $args{temp_dir} || File::Temp->newdir;

  my $result = cpanm {perl_lib_dir_name => $temp_dir->dirname,
                      temp_dir => $temp_dir,
                      scandeps => 1}, $modules;

  my $dist = $result->{output_json}->[0]
      ? $result->{output_json}->[-1]->[0]->{pathname} : undef;

  my $convert_list;
  $convert_list = sub {
    return {
      map {
        (
          $_->[0]->{pathname} =>
          [
            $_->[0]->{module},
            $_->[0]->{module_version},
            $_->[0]->{distvname},
            {
              map {
                (
                  $_->[0]->{pathname} => [
                    $_->[0]->{module},
                    $_->[0]->{module_version},
                    $_->[0]->{distvname},
                  ],
                );
              } @{$_->[1]}
            },
          ],
          %{$convert_list->($_->[1])},
        );
      } @{$_[0]},
    };
  }; # $convert_list;

  $result = $convert_list->($result->{output_json} || {});

  my $package_list = [];

  make_path $deps_json_dir_name;
  for my $path (keys %$result) {
    my $info = $result->{$path};
    my $file_name = $deps_json_dir_name . '/' . $info->[2] . '.json';
    info_writing "json file", $file_name;
    if (-f $file_name) {
      open my $file, '<', $file_name or die "$0: $file_name: $!";
      local $/ = undef;
      my $json = decode_json (<$file>);
      if (defined $json and ref $json eq 'ARRAY' and ref $json->[2] eq 'HASH') {
        for (keys %{$json->[2]}) {
          $info->[3]->{$_} ||= $json->[2]->{$_};
        }
      }
      close $file;
    }
    open my $file, '>', $file_name or die "$0: $file_name: $!";
    print $file encode_json $info;

    push @$package_list, {path => $path, name => $info->[0], version => $info->[1]};
  }

  return {pathname => $dist, package_list => $package_list};
} # scandeps

sub copy_install_jsons () {
  make_path $install_json_dir_name;
  for (glob "$installed_dir_name/lib/perl5/$Config{archname}/.meta/*/install.json") {
    if (m{/([^/]+)/install\.json$}) {
      copy $_ => "$install_json_dir_name/$1.json";
    }
  }
} # copy_install_jsons

# XXX
#copy_install_jsons;
# for (glob "$installed_dir_name/lib/perl5/$Config{archname}/.meta/*/install.json") {
# exit unless -f "}.$dists_dir_name.q{/authors/id/".$data->{pathname};
# for (keys %{$data->{provides}}) {
# $ver = $data->{provides}->{$_}->{version} || "undef";

sub read_package_list ($) {
  my $file_name = shift;
  my $result = [];
  return $result unless -f $file_name;
  open my $file, '<', $file_name or die "$0: $file_name: $!";
  my $has_blank_line;
  while (<$file>) {
    if ($has_blank_line and /^(\S+)\s+(\S+)\s+(\S+)/) {
      push @$result, {path => $3, name => $1, version => $2 eq 'undef' ? undef : $2};
    } elsif (/^$/) {
      $has_blank_line = 1;
    }
  }
  return $result;
} # read_package_list

sub write_package_list ($$) {
  my ($modules => $file_name) = @_;
  my @list;
  for my $module (@$modules) {
    my $mod = $module->{name};
    my $ver = $module->{version} || 'undef';
    push @list, sprintf "%s %s  %s\n",
        length $mod < 32 ? $mod . (" " x (32 - length $mod)) : $mod,
        length $ver < 10 ? (" " x (10 - length $ver)) . $ver : $ver,
        $module->{path};
  }

  info_writing "package list", $file_name;
  mkdir_for_file $file_name;
  open my $details, '>', $file_name or die "$0: $file_name: $!";
  print $details "File: 02packages.details.txt\n";
  print $details "URL: http://www.perl.com/CPAN/modules/02packages.details.txt\n";
  print $details "Description: Package names\n";
  print $details "Columns: package name, version, path\n";
  print $details "Intended-For: Automated fetch routines, namespace documentation.\n";
  print $details "Written-By: pmbp.pl\n";
  print $details "Line-Count: ", scalar @list, "\n";
  print $details "Last-Updated: ", scalar localtime, "\n";
  print $details "\n";
  my %printed;
  print $details join '', sort { $a cmp $b } grep { not $printed{$_}++ } @list;
  close $details;
} # write_package_list

sub destroy_cpanm_home () {
  remove_tree $cpanm_home_dir_name;
} # destroy_cpanm_home

sub destroy () {
  destroy_cpanm_home;
} # destroy

for my $command (@command) {
  if ($command->{type} eq 'install-module') {
    info "Install $command->{module}...";
    install_modules {$command->{module} => ''};
  } elsif ($command->{type} eq 'scandeps') {
    info "Scanning dependency of $command->{module}...";
    my $result = scandeps {$command->{module} => ''}, skip_if_found => 1;
    push @$PackageList, @{$result->{package_list}} if $result;
  } elsif ($command->{type} eq 'read-package-list') {
    my $list = read_package_list $command->{file_name};
    push @$PackageList, @$list;
  } elsif ($command->{type} eq 'write-package-list') {
    write_package_list $PackageList => $command->{file_name};
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
