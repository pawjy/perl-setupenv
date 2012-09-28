use strict;
use warnings;
use Config;
use Cwd qw(abs_path);
use File::Path qw(mkpath rmtree);
use File::Copy qw(copy move);
use File::Temp ();
use File::Spec ();
use Getopt::Long;

my $perl = 'perl';
my $perl_version;
my $wget = 'wget';
my $PerlbrewInstallerURL = q<http://install.perlbrew.pl/>;
my $PerlbrewParallelCount = 1;
my $cpanm_url = q<http://cpanmin.us/>;
my $root_dir_name = '.';
my $pmtar_dir_name;
my $pmpp_dir_name;
my @command;
my @CPANMirror = qw(
  http://search.cpan.org/CPAN
  http://cpan.metacpan.org/
  http://backpan.perl.org/
);
my $Verbose = 0;
my $PreserveInfoFile = 0;
my $ExecuteSystemPackageInstaller = $ENV{TRAVIS} || 0;

my @Argument = @ARGV;

GetOptions (
  '--perl-command=s' => \$perl,
  '--wget-command=s' => \$wget,
  '--perlbrew-installer-url=s' => \$PerlbrewInstallerURL,
  '--perlbrew-parallel-count=s' => \$PerlbrewParallelCount,
  '--cpanm-url=s' => \$cpanm_url,
  '--root-dir-name=s' => \$root_dir_name,
  '--pmtar-dir-name=s' => \$pmtar_dir_name,
  '--pmpp-dir-name=s' => \$pmpp_dir_name,
  '--perl-version=s' => \$perl_version,
  '--verbose' => sub { $Verbose++ },
  '--preserve-info-file' => \$PreserveInfoFile,
  '--execute-system-package-installer' => \$ExecuteSystemPackageInstaller,

  '--install-module=s' => sub {
    my $module = PMBP::Module->new_from_module_arg ($_[1]);
    push @command, {type => 'install-module', module => $module};
  },
  '--install-modules-by-file-name=s' => sub {
    push @command, {type => 'install-modules-by-list', file_name => $_[1]};
  },
  '--install-modules-by-list' => sub {
    push @command, {type => 'install-modules-by-list'};
  },
  '--install-to-pmpp=s' => sub {
    my $module = PMBP::Module->new_from_module_arg ($_[1]);
    push @command, {type => 'install-to-pmpp', module => $module};
  },
  '--install-by-pmpp' => sub {
    push @command, {type => 'install-by-pmpp'};
  },
  '--update-pmpp-by-file-name=s' => sub {
    push @command, {type => 'update-pmpp-by-list', file_name => $_[1]};
  },
  '--update-pmpp-by-list' => sub {
    push @command, {type => 'update-pmpp-by-list'};
  },
  '--scandeps=s' => sub {
    my $module = PMBP::Module->new_from_module_arg ($_[1]);
    push @command, {type => 'scandeps', module => $module};
  },
  '--select-module=s' => sub {
    my $module = PMBP::Module->new_from_module_arg ($_[1]);
    push @command, {type => 'select-module', module => $module};
  },
  '--select-modules-by-file-name=s' => sub {
    push @command, {type => 'select-modules-by-list', file_name => $_[1]};
  },
  '--select-modules-by-list' => sub {
    push @command, {type => 'select-modules-by-list'};
  },
  '--read-module-index=s' => sub {
    push @command, {type => 'read-module-index', file_name => $_[1]};
  },
  '--read-carton-lock=s' => sub {
    push @command, {type => 'read-carton-lock', file_name => $_[1]};
  },
  '--write-module-index=s' => sub {
    push @command, {type => 'write-module-index', file_name => $_[1]};
  },
  '--write-pmb-install-list=s' => sub {
    push @command, {type => 'write-pmb-install-list', file_name => $_[1]};
  },
  '--write-install-module-index=s' => sub {
    push @command, {type => 'write-install-module-index', file_name => $_[1]};
  },
  '--write-libs-txt=s' => sub {
    push @command, {type => 'write-libs-txt', file_name => $_[1]};
  },
  '--write-makefile-pl=s' => sub {
    push @command, {type => 'write-makefile-pl', file_name => $_[1]};
  },
  '--print-perl-core-version=s' => sub {
    push @command, {type => 'print-perl-core-version', module_name => $_[1]};
  },
  '--set-module-index=s' => sub {
    push @command, {type => 'set-module-index', file_name => $_[1]};
  },
  '--prepend-mirror=s' => sub {
    push @command, {type => 'prepend-mirror', url => $_[1]};
  },
  '--print-scanned-dependency=s' => sub {
    push @command, {type => 'print-scanned-dependency', dir_name => $_[1]};
  },
  '--print-module-pathname=s' => sub {
    my $module = PMBP::Module->new_from_module_arg ($_[1]);
    push @command, {type => 'print-module-pathname',
                    module => $module};
  },
  (map {
    my $n = $_;
    ("--$n" => sub {
      push @command, {type => $n};
    });
  } qw(
    update install
    install-perl
    print-latest-perl-version
    print-libs print-pmtar-dir-name
  )),
) or die "Usage: $0 options... (See source for details)\n";

$perl_version ||= `@{[quotemeta $perl]} -e 'printf "%vd", \$^V'`;
$perl_version =~ s/^v//;
unless ($perl_version =~ /\A5\.[0-9]+\.[0-9]+\z/) {
  die "Invalid Perl version: $perl_version\n";
}

sub make_path ($) { mkpath $_[0] }
sub remove_tree ($) { rmtree $_[0] }

make_path $root_dir_name;
$root_dir_name = abs_path $root_dir_name;
my $local_dir_name = $root_dir_name . '/local/perl-' . $perl_version;
my $pmb_dir_name = $local_dir_name . '/pmbp';
my $temp_dir_name = $pmb_dir_name . '/tmp';
my $cpanm_dir_name = $temp_dir_name . '/cpanm';
my $cpanm_home_dir_name = $cpanm_dir_name . '/tmp';
my $cpanm = $cpanm_dir_name . '/bin/cpanm';
my $CPANMWrapper = $cpanm_dir_name . '/bin/cpanmwrapper';
my $cpanm_lib_dir_name = $cpanm_dir_name . '/lib/perl5';
unshift @INC, $cpanm_lib_dir_name; ## Should not use XS modules.
my $installed_dir_name = $local_dir_name . '/pm';
my $log_dir_name = $temp_dir_name . '/logs';
$pmtar_dir_name ||= $root_dir_name . '/deps/pmtar';
$pmpp_dir_name ||= $root_dir_name . '/deps/pmpp';
make_path $pmtar_dir_name;
make_path $pmpp_dir_name;
my $packages_details_file_name = $pmtar_dir_name . '/modules/02packages.details.txt';
my $install_json_dir_name = $pmtar_dir_name . '/meta';
my $deps_json_dir_name = $pmtar_dir_name . '/deps';
my $deps_txt_dir_name = $pmtar_dir_name . '/deps';

## ------ Logging ------

{
  my $InfoNeedNewline = 0;
  my $InfoFile;
  my $InfoFileName;
  
  sub open_info_file () {
    $InfoFileName = "$log_dir_name/pmbp-" . time . "-" . $$ . ".log";
    mkdir_for_file ($InfoFileName);
    open $InfoFile, '>', $InfoFileName or die "$0: $InfoFileName: $!";
    info_writing (0, "operation log file", $InfoFileName);
  } # open_info_file
  
  sub delete_info_file () {
    close $InfoFile;
    unlink $InfoFileName;
  } # delete_info_file
  
  sub info ($$) {
    if ($Verbose >= $_[0]) {
      $InfoNeedNewline--, print STDERR "\n" if $InfoNeedNewline;
      if ($_[1] =~ /\.\.\.\z/) {
        print STDERR $_[1];
        $InfoNeedNewline = 1;
      } else {
        print STDERR $_[1], ($_[1] =~ /\n\z/ ? "" : "\n");
      }
    } else {
      print STDERR ".";
      $InfoNeedNewline = 1;
    }
    print $InfoFile $_[1], ($_[1] =~ /\n\z/ ? "" : "\n");
  } # info
  
  sub info_die ($) {
    $InfoNeedNewline--, print STDERR "\n" if $InfoNeedNewline;
    print $InfoFile $_[0] =~ /\n\z/ ? $_[0] : "$_[0]\n";
    print STDERR $_[0] =~ /\n\z/ ? $_[0] : "$_[0]\n";
    die "$0 failed; See $InfoFileName for details\n";
  } # info_die

  sub info_writing ($$$) {
    info $_[0], join '', "Writing ", $_[1], " ", File::Spec->abs2rel ($_[2]), " ...";
  } # info_writing

  sub info_end () {
    $InfoNeedNewline--, print STDERR "\n" if $InfoNeedNewline;
  } # info_end
}

## ------ Files and directories ------

sub mkdir_for_file ($) {
  my $file_name = $_[0];
  $file_name =~ s{[^/\\]+$}{};
  make_path $file_name;
} # mkdir_for_file

sub copy_log_file ($$) {
  my ($file_name, $module_name) = @_;
  my $log_file_name = $module_name;
  $log_file_name =~ s/::/-/g;
  $log_file_name = "$log_dir_name/@{[time]}-$log_file_name.log";
  mkdir_for_file $log_file_name;
  copy $file_name => $log_file_name or die "Can't save log file: $!\n";
  info_writing 0, "install log file", $log_file_name;
  open my $file, '<', $file_name or die "$0: $file_name: $!";
  local $/ = undef;
  return <$file>;
} # copy_log_file

## ------ Commands ------

sub _quote_dq ($) {
  my $s = shift;
  $s =~ s/\"/\\\"/g;
  return $s;
} # _quote_dq

sub run_command ($;%) {
  my ($command, %args) = @_;
  my $prefix = defined $args{prefix} ? $args{prefix} : '';
  my $envs = $args{envs} || {};
  info 2, qq{$prefix\$ @{[map { $_ . '="' . (_quote_dq $envs->{$_}) . '" ' } sort { $a cmp $b } keys %$envs]}@$command};
  local %ENV = (%ENV, %$envs);
  open my $cmd, "-|", (join ' ', map quotemeta, @$command) . " 2>&1"
      or die "$0: $command->[0]: $!";
  while (<$cmd>) {
    my $level = defined $args{info_level} ? $args{info_level} : 1;
    $level = $args{onoutput}->($_) if $args{onoutput};
    info $level, "$prefix$_";
  }
  return close $cmd;
} # run_command

## ------ Downloading ------

sub _save_url {
  mkdir_for_file $_[1];
  info 1, "Downloading <$_[0]>...";
  run_command [$wget, '-O', $_[1], $_[0]], info_level => 2;
  return -f $_[1];
} # _save_url

sub save_url ($$) {
  _save_url (@_) or die "Failed to download <$_[0]>\n";
} # save_url

## ------ JSON ------

{
  my $json_installed;
  
  sub encode_json ($) {
    unless ($json_installed) {
      $json_installed = 1;
      eval q{ require JSON } or
      install_support_module (PMBP::Module->new_from_package ('JSON'));
    }
    require JSON;
    return JSON->new->utf8->allow_blessed->convert_blessed->allow_nonref->pretty->canonical->encode ($_[0]);
  } # encode_json

  sub decode_json ($) {
    unless ($json_installed) {
      $json_installed = 1;
      eval q{ require JSON } or
      install_support_module (PMBP::Module->new_from_package ('JSON'));
    }
    require JSON;
    return JSON->new->utf8->allow_blessed->convert_blessed->allow_nonref->pretty->canonical->decode ($_[0]);
  } # decode_json
}

sub load_json ($) {
  open my $file, '<', $_[0] or die "$0: $_[0]: $!";
  local $/ = undef;
  my $json = decode_json (<$file>);
  close $file;
  return $json;
} # load_json

## ------ Install system packages ------

{
  my $HasAPT;
  my $HasYUM;
  sub install_system_packages ($) {
    my $packages = $_[0];
    return unless @$packages;
    
    $HasAPT = `which apt-get` =~ /apt/ ? 1 : 0 if not defined $HasAPT;
    $HasYUM = `which yum` =~ /yum/ ? 1 : 0 if not defined $HasYUM;

    my $cmd;
    my $env = '';
    if ($HasAPT) {
      $cmd = ['sudo', '--', 'apt-get', 'install', '-y', map { $_->{debian_name} || $_->{name} } @$packages];
      $env = 'DEBIAN_FRONTEND="noninteractive" ';
    } elsif ($HasYUM) {
      $cmd = ['sudo', '--', 'yum', 'install', '-y', map { $_->{redhat_name} || $_->{name} } @$packages];
    }

    if ($cmd) {
      if (not $ExecuteSystemPackageInstaller) {
        info 0, "Execute following command and retry:";
        info 0, '  ' . $env . '$ ' . join ' ', @$cmd;
      } else {
        info 0, $env . '$ ' . join ' ', @$cmd;
        local $ENV{DEBIAN_FRONTEND} = "noninteractive";
        return run_command $cmd, info_level => 0;
      }
    } else {
      info 0, "Install following packages and retry:";
      info 0, "  " . join ' ', map { $_->{name} } @$packages;
    }
    return 0;
  } # install_system_packages
}

## ------ Installing Perl ------

my $LatestPerlVersion;
sub get_latest_perl_version () {
  return $LatestPerlVersion if $LatestPerlVersion;

  my $file_name = qq<$temp_dir_name/perl.json>;
  save_url q<http://api.metacpan.org/release/perl> => $file_name
      if not -f $file_name or
         [stat $file_name]->[9] + 24 * 60 * 60 < time;
  my $json = load_json $file_name;
  if (ref $json eq 'HASH' and $json->{name} and
      $json->{name} =~ /^perl-([0-9A-Za-z._-]+)$/) {
    return $LatestPerlVersion = $1;
  } else {
    return $LatestPerlVersion = '5.16.1';
  }
} # get_latest_perl_version

sub install_perlbrew () {
  return if -f "$root_dir_name/local/perlbrew/bin/perlbrew";
  save_url $PerlbrewInstallerURL
      => "$root_dir_name/local/install.perlbrew";
  local $ENV{PERLBREW_ROOT} = abs_path "$root_dir_name/local/perlbrew";
  run_command ['sh', "$root_dir_name/local/install.perlbrew"];
  unless (-f "$root_dir_name/local/perlbrew/bin/perlbrew") {
    info_die "Can't install perlbrew";
  }
} # install_perlbrew

sub install_perl () {
  install_perlbrew;
  my $i = 0;
  PERLBREW: {
    $i++;
    my $log_file_name;
    my $redo;
    run_command ["$root_dir_name/local/perlbrew/bin/perlbrew",
                 'install',
                 'perl-' . $perl_version,
                 '--notest',
                 '--as' => 'perl-' . $perl_version,
                 '-j' => $PerlbrewParallelCount],
                envs => {PERLBREW_ROOT => abs_path "$root_dir_name/local/perlbrew"},
                prefix => "perlbrew($i): ",
                onoutput => sub {
                  if ($_[0] =~ m{^  tail -f (.+?/perlbrew/build.perl-.+?\.log)}) {
                    $log_file_name = $1;
                    $log_file_name =~ s{^~/}{$ENV{HOME}/} if defined $ENV{HOME};
                    return 0;
                  } elsif ($_[0] =~ /^It is possible that the compressed file\(s\) have become corrupted/) {
                    remove_tree "$root_dir_name/local/perlbrew/dists";
                    make_path "$root_dir_name/local/perlbrew/dists";
                    $redo = 1;
                    return 1;
                  } else {
                    return 1;
                  }
                };
    
    copy_log_file $log_file_name => "perl-$perl_version"
        if defined $log_file_name;
    unless (-f "$root_dir_name/local/perlbrew/perls/perl-$perl_version/bin/perl") {
      if ($redo and $i < 10) {
        info 0, "perlbrew($i): Failed to install perl-$perl_version; retrying...";
        redo PERLBREW;
      } else {
        info_die "perlbrew($i): Failed to install perl-$perl_version";
      }
    }
  } # PERLBREW
} # install_perl

## ------ cpanm ------

sub install_cpanm () {
  return if -f $cpanm;
  save_url $cpanm_url => $cpanm;
} # install_cpanm

sub install_cpanm_wrapper () {
  return if -f $CPANMWrapper;
  install_cpanm;
  info_writing 1, "cpanm_wrapper", $CPANMWrapper;
  mkdir_for_file $CPANMWrapper;
  open my $file, '>', $CPANMWrapper or die "$0: $CPANMWrapper: $!";
  printf $file q{#!/usr/bin/perl
    BEGIN { require "%s" };

    my $orig_search_module = \&App::cpanminus::script::search_module;
    *App::cpanminus::script::search_module = sub {
      my ($self, $module, $version) = @_;
      if ($module eq 'ExtUtils::MakeMaker' and
          defined $version and
          $version =~ /^(\d+)\.(\d{2})(\d{2})$/) {
        $version = "$1.$2\_$3";
        warn "$module $1.$2$3 -> $version rewritten\n";
      }
      return $orig_search_module->($self, $module, $version);
    }; # search_module
    
    my $app = App::cpanminus::script->new;
    $app->parse_options (@ARGV);
    $app->doit or exit 1;
  }, $cpanm;
  close $file;
} # install_cpanm_wrapper

our $CPANMDepth = 0;
my $cpanm_init = 0;
sub cpanm ($$);
sub cpanm ($$) {
  my ($args, $modules) = @_;
  my $result = {};
  install_cpanm_wrapper;

  my $perl_lib_dir_name = $args->{perl_lib_dir_name}
      || ($args->{info} ? $cpanm_lib_dir_name : undef)
      or die "No |perl_lib_dir_name| specified";

  if (not $args->{info} and @$modules == 1 and
      ref $modules->[0] and $modules->[0]->is_perl) {
    info 1, "cpanm invocation for package |perl| skipped";
    return {};
  }

  local $ENV{HOME} = do {
    ## For Module::Build-based packages (e.g. Class::Accessor::Lvalue)
    require Digest::MD5;
    my $key = Digest::MD5::md5_hex ($perl_lib_dir_name);
    my $home_dir_name = "$cpanm_home_dir_name/$key";
    my $file_name = "$home_dir_name/.modulebuildrc";
    mkdir_for_file $file_name;
    open my $file, '>', $file_name or die "$0: $file_name: $!";
    print $file "install --install-base $perl_lib_dir_name";
    close $file;
    $home_dir_name
  };

  my $redo = 0;
  COMMAND: {
    my @required_cpanm;
    my @required_install;
    my @required_install2;
    my @required_system;

    my @perl_option = ('-I' . $cpanm_lib_dir_name);

    my @option = ($args->{local_option} || '-L' => $perl_lib_dir_name,
                  ($args->{skip_satisfied} ? '--skip-satisfied' : ()),
                  qw(--notest --cascade-search),
                  ($args->{scandeps} ? ('--scandeps', '--format=json', '--force') : ()));
    push @option, '--info' if $args->{info};
    push @option, '--verbose' if $Verbose > 1 and
        not ($args->{scandeps} or $args->{info});

    my @module_arg = map {
      {'GD::Image' => 'GD'}->{$_} || $_;
    } map {
      ref $_ ? $_->as_cpanm_arg ($pmtar_dir_name) : $_;
    } @$modules;
    if (grep { not m{/misc/[^/]+\.tar\.gz$} } @module_arg) {
      push @option, '--save-dists' => $pmtar_dir_name;
    }

    push @option,
        '--mirror' => (abs_path $pmtar_dir_name),
        map { ('--mirror' => $_) } @CPANMirror;

    if (defined $args->{module_index_file_name}) {
      my $mi = abs_path $args->{module_index_file_name};
      push @option, '--mirror-index' => $mi if defined $mi;
    } else {
      get_default_mirror_file_name ();
      unshift @option, '--mirror' => abs_path $cpanm_dir_name;
    }

    #push @option, '--mirror' => abs_path supplemental_module_index ();

    ## Let cpanm not use Web API, as it slows down operations.
    push @option, '--mirror-only';

    local $ENV{LANG} = 'C';
    local $ENV{PERL_CPANM_HOME} = $cpanm_home_dir_name;
    local $ENV{PATH} = (abs_path "$root_dir_name/local/perlbrew/perls/perl-$perl_version/bin") . ':' . $ENV{PATH};
    local $ENV{MP_APXS} = '/usr/sbin/apxs';
    local $ENV{PERLBREW_CONFIGURE_FLAGS} = "-de -Duserelocatableinc ccflags=-fPIC"; # 5.15.5+
    my @cmd = ($perl, 
               @perl_option,
               $CPANMWrapper,
               @option,
               @module_arg);
    info $args->{info} ? 2 : 1,
        join ' ', 'PERL_CPANM_HOME=' . $cpanm_home_dir_name, @cmd;
    my $json_temp_file = File::Temp->new;
    open my $cmd, '-|', ((join ' ', map { quotemeta } @cmd) .
                         ' 2>&1 ' .
                         ($args->{scandeps} || $args->{info}
                              ? ' > ' . quotemeta $json_temp_file : '') .
                         ' < /dev/null')
        or die "Failed to execute @cmd - $!\n";
    my $current_module_name = '';
    my $failed;
    my $remove_inc;
    while (<$cmd>) {
      if (/^! Couldn\'t find module or a distribution /) {
        info 0, "cpanm($CPANMDepth/$redo): $_";
      } else {
        info 1, "cpanm($CPANMDepth/$redo): $_";
      }
      
      if (/Can\'t locate (\S+\.pm) in \@INC/) {
        push @required_cpanm, PMBP::Module->new_from_pm_file_name ($1);
      } elsif (/^Building version-\S+ \.\.\. FAIL/) {
        push @required_install,
            map { PMBP::Module->new_from_package ($_) }
            qw{ExtUtils::MakeMaker ExtUtils::ParseXS};
      } elsif (/^--> Working on (\S)+$/) {
        $current_module_name = $1;
      } elsif (/^skipping .+\/perl-/) {
        if (@module_arg and $module_arg[0] eq 'Module::Metadata') {
          push @required_install, PMBP::Module->new_from_module_arg
              ('Module::Metadata=http://search.cpan.org/CPAN/authors/id/A/AP/APEIRON/Module-Metadata-1.000011.tar.gz');
          $failed = 1;
        }
      } elsif (/^! (?:Installing|Configuring) (\S+) failed\. See (.+?) for details\.$/ or
               /^! Configure failed for (\S+). See (.+?) for details\.$/) {
        my $log = copy_log_file $2 => $1;
        if ($log =~ m{^make(?:\[[0-9]+\])?: .+?ExtUtils/xsubpp}m or
            $log =~ m{^Can\'t open perl script "ExtUtils/xsubpp"}m) {
          push @required_install,
              map { PMBP::Module->new_from_package ($_) }
              qw{ExtUtils::MakeMaker ExtUtils::ParseXS};
        } elsif ($log =~ /^only nested arrays of non-refs are supported at .*?\/ExtUtils\/MakeMaker.pm/m) {
          push @required_install, PMBP::Module->new_from_package ('ExtUtils::MakeMaker');
        } elsif ($log =~ /^Can\'t locate (\S+\.pm) in \@INC/m) {
          push @required_install, PMBP::Module->new_from_pm_file_name ($1);
        } elsif ($log =~ /^String found where operator expected at Makefile.PL line [0-9]+, near \"([0-9A-Za-z_]+)/m) {
          my $module_name = {
              author_tests => 'Module::Install::AuthorTests',
              readme_from => 'Module::Install::ReadmeFromPod',
              readme_markdown_from => 'Module::Install::ReadmeMarkdownFromPod',
          }->{$1};
          push @required_install, PMBP::Module->new_from_package ($module_name)
              if $module_name;
        } elsif ($log =~ /^Bareword "([0-9A-Za-z_]+)" not allowed while "strict subs" in use at Makefile.PL /m) {
          my $module_name = {
              auto_set_repository => 'Module::Install::Repository',
              githubmeta => 'Module::Install::GithubMeta',
              use_test_base => 'Module::Install::TestBase',
          }->{$1};
          push @required_install, PMBP::Module->new_from_package ($module_name)
              if $module_name;
        } elsif ($log =~ /^Can\'t call method "load_all_extensions" on an undefined value at inc\/Module\/Install.pm /m) {
          $remove_inc = 1;
        } elsif ($log =~ /^(\S+) version \S+ required--this is only version \S+/m) {
          push @required_install, PMBP::Module->new_from_package ($1);
        } elsif ($log =~ /^cc: Internal error: Killed \(program cc1\)/m and
                 @module_arg and $module_arg[0] eq 'Net::SSLeay') {
          push @required_install, PMBP::Module->new_from_module_arg
              ('Net::SSLeay~1.36=http://search.cpan.org/CPAN/authors/id/F/FL/FLORA/Net-SSLeay-1.36.tar.gz'); # XXX
        } elsif ($log =~ /^Could not find gdlib-config in the search path. Please install libgd /m) {
          push @required_system,
              {name => 'gd-devel', debian_name => 'libgd2-xpm-dev'};
        } elsif ($log =~ /^version.c:.+?: error: db.h: No such file or directory/m and
                 $log =~ /^-> FAIL Installing DB_File failed/m) {
          push @required_system,
              {name => 'bdb-devel', redhat_name => 'db-devel',
               debian_name => 'libdb-dev'};
        } elsif ($log =~ /^Expat.xs:.+?: error: expat.h: No such file or directory/m) {
          push @required_system,
              {name => 'expat-devel', debian_name => 'libexpat1-dev'};
        } # $log
        $failed = 1;
      } elsif (/^! Couldn\'t find module or a distribution (\S+) \(/) {
        my $mod = {
          'Date::Parse' => 'Date::Parse',
          'Test::Builder::Tester' => 'Test::Simple', # Test-Simple 0.98 < TBT 1.07
        }->{$1};
        push @required_install,
            PMBP::Module->new_from_package ($mod) if $mod;
      }
    }
    info 2, "cpanm done";
    (close $cmd and not $failed) or do {
      unless ($CPANMDepth > 100 or $redo++ > 10) {
        my $redo;
        if ($remove_inc and
            @module_arg and $module_arg[0] =~ m{/} and
            -d "$module_arg[0]/inc") {
          remove_tree "$module_arg[0]/inc";
          $redo = 1;
        }
        if (@required_system) {
          $redo = 1 if install_system_packages \@required_system;
        }
        if (@required_cpanm) {
          local $CPANMDepth = $CPANMDepth + 1;
          for my $module (@required_cpanm) {
            install_support_module ($module);
          }
          $redo = 1;
        } elsif (@required_install) {
          if ($perl_lib_dir_name ne $cpanm_dir_name) {
            local $CPANMDepth = $CPANMDepth + 1;
            for my $module (@required_install) {
              if ($args->{scandeps}) {
                scandeps ($args->{scandeps}->{module_index}, $module,
                          skip_if_found => 1,
                          module_index_file_name => $args->{module_index_file_name});
                push @{$result->{additional_deps} ||= []}, $module;
              }
              cpanm ({perl_lib_dir_name => $perl_lib_dir_name,
                      module_index_file_name => $args->{module_index_file_name}}, [$module])
                  unless $args->{no_install};
            }
            $redo = 1 unless $args->{no_install};
          } else {
            local $CPANMDepth = $CPANMDepth + 1;
            for my $module (@required_install) {
              cpanm ({perl_lib_dir_name => $perl_lib_dir_name,
                      module_index_file_name => $args->{module_index_file_name}}, [$module]);
            }
            $redo = 1;
          }
        }
        redo COMMAND if $redo;
      }
      if ($args->{info}) {
        #
      } elsif ($args->{ignore_errors}) {
        info 0, "cpanm($CPANMDepth): Processing @{[join ' ', map { ref $_ ? $_->as_short : $_ } @$modules]} failed (@{[$? >> 8]}) (Ignored)";
      } else {
        info_die "cpanm($CPANMDepth): Processing @{[join ' ', map { ref $_ ? $_->as_short : $_ } @$modules]} failed (@{[$? >> 8]})\n";
      }
    }; # close or do
    if ($args->{info} and -f $json_temp_file->filename) {
      open my $file, '<', $json_temp_file->filename or die "$0: $!";
      $result->{output_text} = <$file>;
    } elsif ($args->{scandeps} and -f $json_temp_file->filename) {
      $result->{output_json} = load_json $json_temp_file->filename;
    }
  } # COMMAND
  return $result;
} # cpanm

sub destroy_cpanm_home () {
  remove_tree $cpanm_home_dir_name;
} # destroy_cpanm_home

## ------ Downloading modules ------

sub get_default_mirror_file_name () {
  my $file_name = qq<$cpanm_dir_name/modules/02packages.details.txt.gz>;
  if (not -f $file_name or
      [stat $file_name]->[9] + 24 * 60 * 60 < time or
      [stat $file_name]->[7] < 1 * 1024 * 1024) {
    save_url q<http://ftp.jaist.ac.jp/pub/CPAN/modules/02packages.details.txt.gz> => $file_name;
    utime time, time, $file_name;
  }
  return abs_path $file_name;
} # get_default_mirror_file_name

sub supplemental_module_index () {
  return undef;

  my $dir_name = "$temp_dir_name/supplemental";
  my $file_name = "$dir_name/modules/02packages.details.txt";
  return $dir_name if -f ($file_name . '.gz') and
      [stat ($file_name . '.gz')]->[9] + 24 * 60 * 60 > time;
  my $index =  PMBP::ModuleIndex->new_from_arrayref ([
    PMBP::Module->new_from_module_arg ('...'),
  ]);
  write_module_index ($index => $file_name);
  run_command ['gzip', '-f', $file_name];
  return $dir_name;
} # supplemental_module_index

sub get_local_copy_if_necessary ($) {
  my $module = shift;

  my $path = $module->pathname;
  my $url = $module->url;

  if (defined $path and defined $url) {
    $path = "$pmtar_dir_name/authors/id/$path";
    if (not -f $path) {
      save_url $url => $path;
    }
  }
} # get_local_copy_if_necessary

sub save_by_pathname ($$) {
  my ($pathname => $module) = @_;

  my $dest_file_name = "$pmtar_dir_name/authors/id/$pathname";
  if (-f $dest_file_name) {
    $module->{url} = 'file://' . abs_path "$pmtar_dir_name/authors/id/$pathname";
    $module->{pathname} = $pathname;
    return 1;
  }

  for (@CPANMirror) {
    my $mirror = $_;
    $mirror =~ s{/+$}{};
    $mirror .= "/authors/id/$pathname";
    if ($mirror =~ m{^[Hh][Tt][Tt][Pp][Ss]?:}) {
      if (_save_url $mirror => $dest_file_name) {
        $module->{url} = $mirror;
        $module->{pathname} = $pathname;
        return 1;
      }
    } else {
      if (-f $mirror) {
        copy $mirror => $dest_file_name or die "$0: Can't copy $mirror";
        $module->{url} = $mirror;
        $module->{pathname} = $pathname;
        return 1;
      }
    }
  }
  
  return 0;
} # save_by_pathname

## ------ Installing modules ------

sub install_module ($;%) {
  my ($module, %args) = @_;
  get_local_copy_if_necessary $module;
  cpanm {perl_lib_dir_name => $args{pmpp} ? $pmpp_dir_name : $installed_dir_name,
         module_index_file_name => $args{module_index_file_name}},
        [$module];
} # install_module

sub install_support_module ($) {
  my $module = shift;
  get_local_copy_if_necessary $module;
  cpanm {perl_lib_dir_name => $cpanm_dir_name,
         local_option => '-l', skip_satisfied => 1}, [$module];
} # install_support_module

## ------ Detecting module dependency ------

sub scandeps ($$;%) {
  my ($module_index, $module, %args) = @_;

  if ($args{skip_if_found}) {
    my $module_in_index = $module_index->find_by_module ($module);
    if ($module_in_index) {
      my $name = $module_in_index->distvname;
      if (defined $name) {
        my $json_file_name = "$deps_json_dir_name/$name.json";
        return if -f $json_file_name;
      }
    }
  }

  my $temp_dir = $args{temp_dir} || File::Temp->newdir;

  get_local_copy_if_necessary $module;
  my $result = cpanm {perl_lib_dir_name => $temp_dir->dirname,
                      temp_dir => $temp_dir,
                      module_index_file_name => $args{module_index_file_name},
                      scandeps => {module_index => $module_index}}, [$module];

  _scandeps_write_result ($result, $module, $module_index);
} # scandeps

sub _scandeps_write_result ($$$) {
  my ($result, $module, $module_index) = @_;

  my $convert_list;
  $convert_list = sub {
    return (
      map {
        (
          [
            PMBP::Module->new_from_cpanm_scandeps_json_module ($_->[0]),
            PMBP::ModuleIndex->new_from_arrayref ([
              map {
                PMBP::Module->new_from_cpanm_scandeps_json_module ($_->[0]);
              } @{$_->[1]}
            ]),
          ],
          ($convert_list->($_->[1])),
        );
      } @{$_[0]},
    );
  }; # $convert_list;

  my $more = $result->{additional_deps} || [];
  $result = [($convert_list->($result->{output_json} || []))];

  if ($module) {
    for (@$result) {
      if (defined $_->[0]->{pathname} and
          defined $module->{pathname} and
          $_->[0]->{pathname} eq $module->{pathname}) {
        $_->[0]->merge_input_data ($module);
        $_->[1]->add_modules ($more);
      }
    }
  } else {
    @$result = grep {
      my $v = $_->[0]->distvname; not (defined $v and $v =~ m{/});
    } @$result;
  }

  make_path $deps_json_dir_name;
  for my $m (@$result) {
    next unless defined $m->[0]->distvname;
    my $file_name = $deps_json_dir_name . '/' . $m->[0]->distvname . '.json';
    info_writing 1, "json file", $file_name;
    if (-f $file_name) {
      my $json = load_json $file_name;
      if (defined $json and ref $json eq 'ARRAY' and ref $json->[1] eq 'ARRAY') {
        my $mi = PMBP::ModuleIndex->new_from_arrayref ($json->[1]);
        $m->[1]->merge_module_index ($mi);
      }
    }
    open my $file, '>', $file_name or die "$0: $file_name: $!";
    print $file encode_json $m;
  }
  $module_index->merge_modules ([map { $_->[0] } @$result]);
} # scandeps

sub load_deps ($$) {
  my ($module_index, $input_module) = @_;
  my $module = $module_index->find_by_module ($input_module)
      || $input_module;
  return undef unless defined $module->distvname;

  my $result = [];

  my @module = ($module);
  my %done;
  while (@module) {
    my $module = shift @module;
    my $dist = $module->distvname;
    next if not defined $dist;
    next if $done{$dist}++;
    my $json_file_name = "$deps_json_dir_name/$dist.json";
    unless (-f $json_file_name) {
      info 2, "$json_file_name not found";
      return undef;
    }
    my $json = load_json $json_file_name;
    if (defined $json and ref $json eq 'ARRAY') {
      push @module, (PMBP::ModuleIndex->new_from_arrayref ($json->[1])->to_list);
      unshift @$result, PMBP::Module->new_from_jsonable ($json->[0]);
    }
  }
  return $result;
} # load_deps

## ------ pmtar and pmpp repositories ------

sub init_pmtar_git () {
  return if -f "$pmtar_dir_name/.git/config";
  run_command ['sh', '-c', "cd \Q$pmtar_dir_name\E && git init"];
} # init_pmtar_git

sub init_pmpp_git () {
  return if -f "$pmpp_dir_name/.git/config";
  run_command ['sh', '-c', "cd \Q$pmpp_dir_name\E && git init"];
} # init_pmpp_git

sub copy_pmpp_modules () {
  delete_pmpp_arch_dir ();
  require File::Find;
  my $from_base_path = abs_path $pmpp_dir_name;
  my $to_base_path = abs_path $installed_dir_name;
  File::Find::find (sub {
    my $rel = File::Spec->abs2rel ((abs_path $_), $from_base_path);
    my $dest = File::Spec->rel2abs ($rel, $to_base_path);
    if (-f $_) {
      info 2, "Copying file $rel...";
      unlink $dest if -f $dest;
      copy $_ => $dest or die "$0: $dest: $!";
    } elsif (-d $_) {
      info 2, "Copying directory $rel...";
      make_path $dest;
    }
  }, $_) for grep { -d $_ } "$pmpp_dir_name/bin", "$pmpp_dir_name/lib";
} # copy_pmpp_modules

sub delete_pmpp_arch_dir () {
  info 1, "rm -fr $pmpp_dir_name/lib/perl5/$Config{archname}";
  remove_tree "$pmpp_dir_name/lib/perl5/$Config{archname}";
} # delete_pmpp_arch_dir

## ------ Module lists ------

sub select_module ($$$;%) {
  my ($src_module_index => $module => $dest_module_index, %args) = @_;
  
  my $mods = load_deps $src_module_index => $module;
  unless ($mods) {
    info 0, "Scanning dependency of @{[$module->as_short]}...";
    scandeps $src_module_index, $module, %args;
    $mods = load_deps $src_module_index => $module;
    unless ($mods) {
      if ($module->is_perl) {
        $mods = [];
      } elsif (defined $module->pathname) {
        if (save_by_pathname $module->pathname => $module) {
          scandeps $src_module_index, $module, %args;
          $mods = load_deps $src_module_index => $module;
        }
      } elsif (defined $module->package and defined $module->version) {
        ## This is an unreliable heuristics...
        my $current_module = $src_module_index->find_by_module
            (PMBP::Module->new_from_package ($module->package));
        if ($current_module) {
          my $path = $current_module->pathname;
          if (defined $path and $path =~ s{-[0-9A-Za-z.+-]+\.(tar\.(?:gz|bz2)|zip)$}{-@{[$module->version]}.$1}) {
            if (save_by_pathname $path => $module) {
              scandeps $src_module_index, $module, %args;
              $mods = load_deps $src_module_index => $module;
            }
          }
        }
      } # version
      die "Can't detect dependency of @{[$module->as_short]}\n" unless $mods;
    }
  }
  $dest_module_index->merge_modules ($mods);
} # select_module

sub read_module_index ($$) {
  my ($file_name => $module_index) = @_;
  unless (-f $file_name) {
    info 0, "$file_name not found; skipped\n";
    return;
  }
  open my $file, '<', $file_name or die "$0: $file_name: $!";
  my $has_blank_line;
  my $modules = [];
  while (<$file>) {
    if ($has_blank_line and /^(\S+)\s+(\S+)\s+(\S+)/) {
      push @$modules, PMBP::Module->new_from_indexable ([$1, $2, $3]);
    } elsif (/^$/) {
      $has_blank_line = 1;
    }
  }
  $module_index->merge_modules ($modules);
} # read_module_index

sub write_module_index ($$) {
  my ($module_index => $file_name) = @_;
  my @list;
  for my $module (($module_index->to_list)) {
    my $mod = $module->package;
    next unless defined $mod;
    my $ver = $module->version;
    $ver = 'undef' if not defined $ver;
    push @list, sprintf "%s %s  %s\n",
        length $mod < 32 ? $mod . (" " x (32 - length $mod)) : $mod,
        length $ver < 10 ? (" " x (10 - length $ver)) . $ver : $ver,
        $module->pathname;
  }

  info_writing 0, "package list", $file_name;
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
} # write_module_index

sub read_pmb_install_list ($$;%) {
  my ($file_name => $module_index, %args) = @_;
  unless (-f $file_name) {
    info 0, "$file_name not found; skipped\n";
    return;
  }
  open my $file, '<', $file_name or die "$0: $file_name: $!";
  my $modules = [];
  while (<$file>) {
    if (/^\s*\#/ or /^\s*$/) {
      #
    } else {
      s/^\s+//;
      s/\s+$//;
      my $module = PMBP::Module->new_from_module_arg ($_);
      next if {
        map { $_ => 1 } qw(
          perl strict warnings base lib encoding utf8 overload
          constant vars integer
          Config
        ),
      }->{$module->package || ''};
      push @$modules, $module;
    }
  }
  $module_index->merge_modules ($modules);
} # read_pmb_install_list

sub write_pmb_install_list ($$) {
  my ($module_index => $file_name) = @_;
  
  my $result = [];
  
  for my $module (($module_index->to_list)) {
    push @$result, [$module->package, $module->version];
  }

  info_writing 0, "pmb-install list", $file_name;
  mkdir_for_file $file_name;
  open my $file, '>', $file_name or die "$0: $file_name: $!";
  my $found = {};
  for (@$result) {
    my $v = (defined $_->[0] ? $_->[0] : '') . (defined $_->[1] ? '~' . $_->[1] : '');
    next if $found->{$v}++;
    print $file $v . "\n";
  }
  close $file;
} # write_pmb_install_list

sub write_install_module_index ($$) {
  my ($module_index => $file_name) = @_;
  write_module_index $module_index => $file_name;
} # write_install_module_index

sub read_carton_lock ($$) {
  my ($file_name => $module_index) = @_;
  my $json = load_json $file_name;
  my $modules = [];
  for (values %{$json->{modules}}) {
    push @$modules, PMBP::Module->new_from_carton_lock_entry ($_);
  }
  $module_index->merge_modules ($modules);
} # read_carton_lock

## ------ Detecting application dependency ------

sub read_install_list ($$;%);
sub read_install_list ($$;%) {
  my ($dir_name => $module_index, %args) = @_;

  THIS: {
    ## pmb install list format
    my @file = map { (glob "$_/config/perl/modules*.txt") } $dir_name;
    if (@file) {
      read_pmb_install_list $_ => $module_index for @file;
      last THIS;
    }

    ## carton.lock
    my $file_name = "$dir_name/carton.lock";
    if (-f $file_name) {
      read_carton_lock $file_name => $module_index;
      last THIS;
    }

    ## cpanfile
    if (-f "$dir_name/cpanfile") {
      ## At the time of writing, cpanm can't be used to obtain list of
      ## required modules from cpanfile (though it does support
      ## cpanfile for module installation).
      get_dependency_from_cpanfile ("$dir_name/cpanfile" => $module_index);
      last THIS;
    }
    
    ## CPAN package configuration scripts
    if (-f "$dir_name/Build.PL" or -f "$dir_name/Makefile.PL") {
      my $temp_dir = File::Temp->newdir;
      my $result = cpanm {perl_lib_dir_name => $temp_dir->dirname,
                          temp_dir => $temp_dir,
                          scandeps => {module_index => $module_index}},
                         [$dir_name];
      _scandeps_write_result ($result, undef, $module_index);
      last THIS;
    }

    ## From *.pm, *.pl, and *.t
    my $mod_names = scan_dependency_from_directory ($dir_name);
    my $modules = [];
    for (keys %$mod_names) {
      info 2, "$dir_name requires $_";
      push @$modules, PMBP::Module->new_from_package ($_);
    }
    $module_index->merge_modules ($modules);
    last THIS;
  } # THIS

  ## Submodules
  return unless $args{recursive};
  for my $dir_name (map { glob "$dir_name/$_" } qw(
    modules/* t_deps/modules/* local/submodules/*
  )) {
    read_install_list $dir_name => $module_index,
        recursive => $args{recursive} ? $args{recursive} - 1 : 0;
  }
} # read_install_list

sub get_dependency_from_cpanfile ($$) {
  my ($file_name => $module_index) = @_;

  install_support_module PMBP::Module->new_from_package ('Module::CPANfile');
  install_support_module PMBP::Module->new_from_package ('CPAN::Meta::Prereqs'); # loaded by Module::CPANfile
  install_support_module PMBP::Module->new_from_package ('CPAN::Meta::Requirements');

  require Module::CPANfile;
  my $cpanfile = Module::CPANfile->load ($file_name);
  my $prereq = $cpanfile->prereq;

  require CPAN::Meta::Requirements;
  my $req = CPAN::Meta::Requirements->new;
  $req->add_requirements ($prereq->requirements_for ('build', 'requires'));
  $req->add_requirements ($prereq->requirements_for ('runtime', 'requires'));
  $req->add_requirements ($prereq->requirements_for ('test', 'requires'));

  my $modules = [];
  for (keys %{$req->as_string_hash}) {
    push @$modules, PMBP::Module->new_from_package ($_);
  }
  $module_index->merge_modules ($modules);
} # get_dependency_from_cpanfile

sub scan_dependency_from_directory ($) {
  my $dir_name = abs_path shift;

  my $modules = {};

  my @include_dir_name = qw(bin lib script t t_deps);
  my @exclude_pattern = map { "^$_" } qw(modules t_deps/modules t_deps/projects);
  for (split /\n/, qx{cd \Q$dir_name\E && find @{[join ' ', grep quotemeta, @include_dir_name]} @{[join ' ', map { "| grep -v $_" } grep quotemeta, @exclude_pattern]} | grep "\\.\\(pm\\|pl\\|t\\)\$" | xargs grep "\\(use\\|require\\) " --no-filename}) {
    s/\#.*$//;
    if (/(?:use|require)\s*(?:base|parent)\s*(.+)/) {
      my $base = $1;
      while ($base =~ /([0-9A-Za-z_:]+)/g) {
        $modules->{$1} = 1;
      }
    } elsif (/(?:use|require)\s*([0-9A-Za-z_:]+)/) {
      my $name = $1;
      next if $name =~ /["']/;
      $modules->{$name} = 1;
    }
  }

  @include_dir_name = map { glob "$dir_name/$_" } qw(lib t/lib modules/*/lib t_deps/modules/*/lib);
  for (split /\n/, qx{cd \Q$dir_name\E && find @{[join ' ', grep quotemeta, @include_dir_name]} | grep "\\.\\(pm\\|pl\\)\$" | xargs grep "package " --no-filename}) {
    if (/package\s*([0-9A-Za-z_:]+)/) {
      delete $modules->{$1};
    }
  }

  delete $modules->{$_} for qw(
    q qw qq
    strict warnings base lib encoding utf8 overload
    constant vars integer
    Config
  );
  for (keys %$modules) {
    delete $modules->{$_} unless /\A[0-9A-Za-z_]+(?:::[0-9A-Za-z_]+)*\z/;
    delete $modules->{$_} if /^[0-9._]+$/;
  }

  return $modules;
} # scan_dependency_from_directory

## ------ Library paths ------

sub get_lib_dir_names () {
  my @lib = grep { defined } map { abs_path $_ } map { glob $_ }
      qq{$root_dir_name/lib},
      qq{$root_dir_name/modules/*/lib},
      qq{$root_dir_name/local/submodules/*/lib},
      qq{$installed_dir_name/lib/perl5/$Config{archname}},
      qq{$installed_dir_name/lib/perl5};
  return @lib;
} # get_lib_dir_names

sub get_libs_txt_file_name () {
  return "$root_dir_name/local/config/perl/libs-$perl_version-$Config{archname}.txt";
} # get_libs_txt_file_name

## ------ Cleanup ------

sub destroy () {
  destroy_cpanm_home;
} # destroy

## ------ Main ------

my $global_module_index = PMBP::ModuleIndex->new_empty;
my $selected_module_index = PMBP::ModuleIndex->new_empty;
my $module_index_file_name;
my $pmpp_touched;
my $start_time = time;
open_info_file;
info 6, '$ ' . join ' ', @Argument;
info 6, sprintf 'Perl %vd (%s)', $^V, $Config{archname};
info 6, '@INC = ' . join ' ', @INC;

while (@command) {
  my $command = shift @command;
  if ($command->{type} eq 'update') {
    my $module_list_file_name = "$root_dir_name/deps/pmtar/modules/index.txt";
    my $pmb_install_file_name = "$root_dir_name/config/perl/pmb-install.txt";
    unshift @command,
        {type => 'read-module-index',
         file_name => $module_list_file_name},
        {type => 'set-module-index'},
        {type => 'init-pmtar-git'},
        {type => 'select-modules-by-list'},
        {type => 'write-module-index',
         file_name => $module_list_file_name},
        {type => 'write-pmb-install-list',
         file_name => $pmb_install_file_name},
        {type => 'init-pmpp-git'},
        {type => 'set-module-index',
         file_name => $module_list_file_name},
        {type => 'update-pmpp-by-list',
         file_name => $pmb_install_file_name},
        {type => 'write-module-index',
         file_name => $module_list_file_name};
  } elsif ($command->{type} eq 'install') {
    my $module_list_file_name = "$root_dir_name/deps/pmtar/modules/index.txt";
    my $pmb_install_file_name = "$root_dir_name/config/perl/pmb-install.txt";
    unshift @command,
        {type => 'read-module-index',
         file_name => $module_list_file_name},
        {type => 'set-module-index',
         file_name => $module_list_file_name},
        {type => 'install-by-pmpp'},
        {type => 'install-modules-by-list',
         file_name => -f $pmb_install_file_name
                          ? $pmb_install_file_name : undef},
        {type => 'write-libs-txt'},
        {type => 'create-libs-txt-symlink'};

  } elsif ($command->{type} eq 'print-latest-perl-version') {
    print get_latest_perl_version;
  } elsif ($command->{type} eq 'install-perl') {
    info 0, "Installing Perl $perl_version...";
    install_perl;

  } elsif ($command->{type} eq 'install-module') {
    delete_pmpp_arch_dir if $pmpp_touched;
    info 0, "Installing @{[$command->{module}->as_short]}...";
    install_module $command->{module},
        module_index_file_name => $module_index_file_name;
  } elsif ($command->{type} eq 'install-modules-by-list') {
    delete_pmpp_arch_dir if $pmpp_touched;
    my $module_index = PMBP::ModuleIndex->new_empty;
    if (defined $command->{file_name}) {
      read_pmb_install_list $command->{file_name} => $module_index;
    } else {
      read_install_list $root_dir_name => $module_index;
    }
    for ($module_index->to_list) {
      info 0, "Installing @{[$_->as_short]}...";
      install_module $_, module_index_file_name => $module_index_file_name;
    }
  } elsif ($command->{type} eq 'install-to-pmpp') {
    info 0, "Installing @{[$command->{module}->as_short]} to pmpp...";
    install_module $command->{module},
        module_index_file_name => $module_index_file_name, pmpp => 1;
    $pmpp_touched = 1;
  } elsif ($command->{type} eq 'install-by-pmpp') {
    info 0, "Copying pmpp modules...";
    copy_pmpp_modules;
  } elsif ($command->{type} eq 'update-pmpp-by-list') {
    my $module_index = PMBP::ModuleIndex->new_empty;
    if (defined $command->{file_name}) {
      read_pmb_install_list $command->{file_name} => $module_index;
    } else {
      read_install_list $root_dir_name => $module_index;
    }
    for ($module_index->to_list) {
      info 0, "Installing @{[$_->as_short]} to pmpp...";
      install_module $_, module_index_file_name => $module_index_file_name, pmpp => 1;
    }
    $pmpp_touched = 1;
  } elsif ($command->{type} eq 'scandeps') {
    info 0, "Scanning dependency of @{[$command->{module}->as_short]}...";
    scandeps $global_module_index, $command->{module},
        skip_if_found => 1,
        module_index_file_name => $module_index_file_name;
  } elsif ($command->{type} eq 'select-module') {
    select_module $global_module_index => $command->{module} => $selected_module_index,
        module_index_file_name => $module_index_file_name;
    $global_module_index->merge_module_index ($selected_module_index);
  } elsif ($command->{type} eq 'select-modules-by-list') {
    my $module_index = PMBP::ModuleIndex->new_empty;
    if (defined $command->{file_name}) {
      read_pmb_install_list $command->{file_name} => $module_index;
    } else {
      read_install_list $root_dir_name => $module_index,
          recursive => 1;
    }
    select_module $global_module_index => $_ => $selected_module_index,
        module_index_file_name => $module_index_file_name
        for ($module_index->to_list);
    $global_module_index->merge_module_index ($selected_module_index);
  } elsif ($command->{type} eq 'read-module-index') {
    read_module_index $command->{file_name} => $global_module_index;
  } elsif ($command->{type} eq 'read-carton-lock') {
    read_carton_lock $command->{file_name} => $global_module_index;
  } elsif ($command->{type} eq 'write-module-index') {
    write_module_index $global_module_index => $command->{file_name};
  } elsif ($command->{type} eq 'write-pmb-install-list') {
    write_pmb_install_list $selected_module_index => $command->{file_name};
  } elsif ($command->{type} eq 'write-install-module-index') {
    write_install_module_index $selected_module_index => $command->{file_name};
  } elsif ($command->{type} eq 'write-libs-txt') {
    my $file_name = $command->{file_name};
    $file_name = get_libs_txt_file_name unless defined $file_name;
    mkdir_for_file $file_name;
    open my $file, '>', $file_name or die "$0: $file_name: $!";
    info_writing 0, "lib paths", $file_name;
    print $file join ':', (get_lib_dir_names);
  } elsif ($command->{type} eq 'create-libs-txt-symlink') {
    my $real_name = get_libs_txt_file_name;
    my $link_name = "$root_dir_name/config/perl/libs.txt";
    mkdir_for_file $link_name;
    unlink $link_name or die "$0: $link_name: $!" if -f $link_name;
    symlink $real_name => $link_name or die "$0: $link_name: $!";
  } elsif ($command->{type} eq 'write-makefile-pl') {
    mkdir_for_file $command->{file_name};
    open my $file, '>', $command->{file_name}
        or die "$0: $command->{file_name}: $!";
    info_writing 0, "dummy Makefile.PL", $command->{file_name};
    print $file q{
      use inc::Module::Install;
      name "Dummy";
      open my $file, "<", "config/perl/pmb-install.txt"
          or die "$0: config/perl/pmb-install.txt: $!";
      while (<$file>) {
        if (/^([0-9A-Za-z_:]+)/) {
          requires $1;
        }
      }
      Meta->write;
      Meta->write_mymeta_json;
    };
  } elsif ($command->{type} eq 'print-libs') {
    print join ':', (get_lib_dir_names);
  } elsif ($command->{type} eq 'set-module-index') {
    $module_index_file_name = $command->{file_name}; # or undef
  } elsif ($command->{type} eq 'prepend-mirror') {
    if ($command =~ m{^[^/]}) {
      $command->{url} = abs_path $command->{url};
    }
    unshift @CPANMirror, $command->{url};
  } elsif ($command->{type} eq 'print-pmtar-dir-name') {
    print $pmtar_dir_name;
  } elsif ($command->{type} eq 'init-pmtar-git') {
    init_pmtar_git;
  } elsif ($command->{type} eq 'init-pmpp-git') {
    init_pmpp_git;
  } elsif ($command->{type} eq 'print-scanned-dependency') {
    my $mod_names = scan_dependency_from_directory $command->{dir_name};
    print map { $_ . "\n" } sort { $a cmp $b } keys %$mod_names;
  } elsif ($command->{type} eq 'print-perl-core-version') {
    install_support_module PMBP::Module->new_from_package ('Module::CoreList');
    require Module::CoreList;
    print Module::CoreList->first_release ($command->{module_name});
  } elsif ($command->{type} eq 'print-module-pathname') {
    my $pathname = $command->{module}->pathname;
    print $pathname if defined $pathname;
  } else {
    die "Command |$command->{type}| is not defined";
  }
} # while @command

delete_pmpp_arch_dir if $pmpp_touched;
destroy;
info 0, "Done: " . (time - $start_time) . " s";
info_end;
delete_info_file unless $PreserveInfoFile;

## ------ End of main ------

package PMBP::Module;
use Carp;

sub new_from_package ($$) {
  return bless {package => $_[1]}, $_[0];
} # new_from_package

sub new_from_pm_file_name ($$) {
  my $m = $_[1];
  $m =~ s/\.pm$//;
  $m =~ s{[/\\]+}{::}g;
  return bless {package => $m}, $_[0];
} # new_from_pm_file_name

sub new_from_module_arg ($$) {
  my ($class, $arg) = @_;
  if (not defined $arg) {
    croak "Module argument is not specified";
  } elsif ($arg =~ /\A([0-9A-Za-z_:]+)\z/) {
    return bless {package => $1}, $class;
  } elsif ($arg =~ /\A([0-9A-Za-z_:]+)~([0-9A-Za-z_.-]+)\z/) {
    return bless {package => $1, version => $2}, $class;
  } elsif ($arg =~ m{\A([0-9A-Za-z_:]+)=([Hh][Tt][Tt][Pp][Ss]?://.+)\z}) {
    my $self = bless {package => $1, url => $2}, $class;
    $self->_set_distname;
    return $self;
  } elsif ($arg =~ m{\A([0-9A-Za-z_:]+)~([0-9A-Za-z_.-]+)=([Hh][Tt][Tt][Pp][Ss]?://.+)\z}) {
    my $self = bless {package => $1, version => $2, url => $3}, $class;
    $self->_set_distname;
    return $self;
  } elsif ($arg =~ m{\A([Hh][Tt][Tt][Pp][Ss]?://.+)\z}) {
    warn "URL without module name ($1) is specified; installing modules without module name is not supported\n";
    my $self = bless {url => $1}, $class;
    $self->_set_distname;
    return $self;
  } else {
    croak "Module argument |$arg| is not supported";
  }
} # new_from_module_arg

sub new_from_cpanm_scandeps_json_module ($$) {
  my ($class, $json) = @_;
  return bless {package => $json->{module},
                version => $json->{module_version},
                distvname => $json->{distvname} || $json->{dir},
                pathname => $json->{pathname} || (defined $json->{dir} ? 'misc/' . $json->{dir} . '.tar.gz' : undef)}, $class;
} # new_from_cpanm_scandeps_json_module

sub new_from_carton_lock_entry ($$) {
  my ($class, $json) = @_;
  return bless {package => $json->{target} || $json->{name},
                version => $json->{version},
                pathname => $json->{pathname}}, $class;
} # new_from_carton_lock_entry

sub new_from_jsonable ($$) {
  return bless $_[1], $_[0];
} # new_from_jsonable

sub new_from_indexable ($$) {
  return bless {package => $_[1]->[0],
                version => $_[1]->[1] eq 'undef' ? undef : $_[1]->[1],
                pathname => $_[1]->[2]}, $_[0];
} # new_from_indexable

sub _set_distname ($) {
  my $self = shift;

  if (not defined $self->{pathname} and defined $self->{url}) {
    if ($self->{url} =~ m{/authors/id/(.+\.(?:tar\.(?:gz|bz2)|zip))$}) {
      $self->{pathname} = $1;
    } elsif ($self->{url} =~ m{([^/]+\.(?:tar\.(?:gz|bz2)|zip))$}) {
      $self->{pathname} = "misc/$1";
    }
  }
} # _set_distname

sub package ($) {
  return $_[0]->{package};
} # package

sub version ($) {
  return $_[0]->{version};
} # version

sub pathname ($) {
  return $_[0]->{pathname} if exists $_[0]->{pathname};

  if (defined $_[0]->{package}) {
    my $result = main::cpanm {info => 1}, [$_[0]];
    if (defined $result->{output_text} and
        $result->{output_text} =~ m{^([A-Z0-9]+)/((?:modules/)?[A-Za-z0-9_.+-]+)$}) {
      return $_[0]->{pathname} = join '/', 
          (substr $1, 0, 1),
          (substr $1, 0, 2),
          $1,
          $2;
    }
  }

  return $_[0]->{pathname} = undef;
} # pathname

sub distvname ($) {
  my $self = shift;
  return $self->{distvname} if defined $self->{distvname};

  my $pathname = $self->pathname;
  if (defined $pathname) {
    $pathname =~ s{^.+/}{};
    $pathname =~ s{\.(?:tar\.(?:gz|bz2)|zip)$}{};
    return $self->{distvname} = $pathname;
  }
  return $self->{distvname} = undef;
} # distvname

sub is_perl ($) {
  my $self = shift;
  my $dist = $self->distvname;
  return $dist && $dist =~ /^perl-[0-9.]+$/;
} # is_perl

sub url ($) {
  return $_[0]->{url};
} # url

sub is_equal_module ($$) {
  my ($m1, $m2) = @_;
  return 0 if not defined $m1->{package} or not defined $m2->{package};
  return 0 if $m1->{package} ne $m2->{package};
  return 0 if defined $m1->{version} and not defined $m2->{version};
  return 0 if not defined $m1->{version} and defined $m2->{version};
  return 0 if defined $m1->{version} and defined $m2->{version} and
              $m1->{version} ne $m2->{version};
  return 1;
} # is_equal_module

sub merge_input_data ($$) {
  my ($m1, $m2) = @_;
  if (not defined $m1->{package}) {
    $m1->{package} = $m2->{package};
    $m1->{version} = $m2->{version};
    $m1->{distvname} ||= $m2->{distvname} if defined $m2->{distvname};
    $m1->{pathname} ||= $m2->{pathname} if defined $m2->{pathname};
    $m1->{url} ||= $m2->{url} if defined $m2->{url};
  }
} # merge_input_data

sub as_short ($) {
  my $self = shift;
  return (defined $self->{package} ? $self->{package} : '') . (defined $self->{version} ? '~' . $self->{version} : '');
} # as_short

sub as_cpanm_arg ($$) {
  my ($self, $pmtar_dir_name) = @_;
  if ($self->{url}) {
    if (defined $self->{pathname}) {
      if ($self->{pathname} =~ m{^misc/}) {
        return $pmtar_dir_name . '/authors/id/' . $self->{pathname};
      } else {
        return $self->{pathname};
      }
    } else {
      return $self->{url};
    }
  } else {
    if ($self->{package} =~ /^inc::Module::Install::/) {
      my $p = $self->{package};
      $p =~ s/^inc:://;
      return $p;
    } else {
      return $self->{package};
    }
  }
} # as_cpanm_arg

sub TO_JSON ($) {
  return {%{$_[0]}};
} # TO_JSON

package PMBP::ModuleIndex;

sub new_empty ($) {
  return bless {list => []}, $_[0];
} # new_empty

sub new_from_arrayref ($$) {
  return bless {list => [map { ref $_ eq 'HASH' ? PMBP::Module->new_from_jsonable ($_) : $_ } @{$_[1]}]}, $_[0];
} # new_from_arrayref

sub find_by_module ($$) {
  return undef unless defined $_[1]->package;
  for (@{$_[0]->{list}}) {
    if ($_->is_equal_module ($_[1]) or
        (not defined $_[1]->version and
         defined $_->package and
         $_->package eq $_[1]->package)) {
      return $_;
    }
  }
  return undef;
} # find_by_module

sub add_modules ($$) {
  push @{$_[0]->{list}}, @{$_[1]};
} # add_modules

sub merge_modules {
  my ($i1, $i2) = @_;
  my @m;
  for my $m (@$i2) {
    unless ($i1->find_by_module ($m)) {
      push @m, $m;
    }
  }
  $i1->add_modules (\@m);
} # merge_modules

sub merge_module_index {
  my ($i1, $i2) = @_;
  my @m;
  for my $m (($i2->to_list)) {
    unless ($i1->find_by_module ($m)) {
      push @m, $m;
    }
  }
  $i1->add_modules (\@m);
} # merge_module_index

sub to_list ($) {
  return @{$_[0]->{list}};
} # to_list

sub TO_JSON ($) {
  return $_[0]->{list};
} # TO_JSON

__END__

=head1 OPTIONS

XXX

=head2 Normal options

=over 4

=item --root-dir-name="path/to/dir"

Specify the root directory of the application.  Various operations by
the script is performed relative to this directory.  The value must be
a valid path to the directory in the platform.  Unless specified, the
current directory is used as the root directory.  If there is no such
a directory, it is first created by the script.  Anyway, the directory
must be writable by the user executing the script.

=item --perl-version="5.n.m"

Specify the Perl version in use.  If the C<--install-perl> command is
invoked, then the value must be one of Perl versions.  Otherwise, it
must match the version of the default C<perl> program.  If this option
is not specified, the version of the default C<perl> program is used.
In this context, the default C<perl> refers to the C<perl> interpreter
used when the C<perl> command is invoked under the current C<PATH>
environment variable.

=item --wget-command="wget"

Specify the "wget" command and arguments, if desired.  By default,
C<wget> is used.

=item --execute-system-package-installer

If the option is specified, or if the C<TRAVIS> environment variable
is se to a true value, the required package detected by the script is
automatically installed.  Please note that the script execute the
package manager with C<sudo> command such that you might be requested
to input sudo password to continue installation.

Otherwise, the suggested system packages are printed to the standard
error output and the installer is not automatically invoked.

At the time of writing, C<apt-get> (for Debian) and C<yum> (for
Fedora) are supported.

=item --perlbrew-installer-url="URL"

Specify the URL of the perlbrew installer.  The default URL is
C<http://install.perlbrew.pl/>.

=item --perlbrew-parallel-count="integer"

Specify the number of parallel processes of perlbrew (used for the
C<-j> option to the C<perlbrew>'s C<install> command).

=back

=head2 Commands

=over 4

=item --print-latest-perl-version

Print the version number of the latest stable release of Perl to the
standard output.  At the time of writing, this command prints the
string C<5.16.1>.

=item --install-perl

Install the Perl with the version specified by the C<--perl-version>
option, using the C<perlbrew> program.  The C<perlbrew> program is
automatically installed under the C<local> directory.  The Perl of the
specified version is also installed into the C<local> directory.  If
the C<perl> with specified version has already been installed, this
command has no effect.

This command should be invoked before any other command where
possible.  In particular, installing modules before the
C<--install-perl> command could make the installed module broken.

=item --print-perl-core-version="Perl::Module::Name"

Print the first version of Perl where the specified module is bundled
as a core module, as returned by L<Module::CoreList>.  For example,
C<5.007003> is printed if the module specified is C<Encode>.  The
L<Module::CoreList> module is automatically installed for the script
if not available.  If the specified module is not part of core Perl
distribution, nothing is printed.

=back

=head1 DEPENDENCY

Perl 5.8 or later is supported by this script.  Core modules of Perl
5.8 must be available.

In addition, the C<wget> command must be available.  Some of commands
(in particular, the C<--update> command) requires the C<git> command.

Though the script depends on C<perlbrew> and C<cpanm> commands, they
are automatically downloaded from the Internet such that you don't
have to prepare these scripts.

=head1 LICENSE

Copyright 2012 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
