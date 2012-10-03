use strict;
use warnings;
use Config;
use Cwd qw(abs_path);
use File::Path qw(mkpath rmtree);
use File::Copy qw(copy move);
use File::Temp ();
use File::Spec ();
use Getopt::Long;

my $PerlCommand = 'perl';
my $SpecifiedPerlVersion;
my $WgetCommand = 'wget';
my $SudoCommand = 'sudo';
my $AptGetCommand = 'apt-get';
my $YumCommand = 'yum';
my $PerlbrewInstallerURL = q<http://install.perlbrew.pl/>;
my $PerlbrewParallelCount = 1;
my $CPANMURL = q<http://cpanmin.us/>;
my $RootDirName = '.';
my $PMTarDirName;
my $PMPPDirName;
my @Command;
my @CPANMirror = qw(
  http://search.cpan.org/CPAN
  http://cpan.metacpan.org/
  http://backpan.perl.org/
);
my $Verbose = $ENV{PMBP_VERBOSE} || 0;
my $PreserveInfoFile = 0;
my $DumpInfoFileBeforeDie = $ENV{TRAVIS} || 0;
my $ExecuteSystemPackageInstaller = $ENV{TRAVIS} || 0;

my @Argument = @ARGV;

GetOptions (
  '--perl-command=s' => \$PerlCommand,
  '--wget-command=s' => \$WgetCommand,
  '--sudo-command=s' => \$SudoCommand,
  '--apt-get-command=s' => \$AptGetCommand,
  '--yum-command=s' => \$YumCommand,
  '--perlbrew-installer-url=s' => \$PerlbrewInstallerURL,
  '--perlbrew-parallel-count=s' => \$PerlbrewParallelCount,
  '--cpanm-url=s' => \$CPANMURL,
  '--root-dir-name=s' => \$RootDirName,
  '--pmtar-dir-name=s' => \$PMTarDirName,
  '--pmpp-dir-name=s' => \$PMPPDirName,
  '--perl-version=s' => \$SpecifiedPerlVersion,
  '--verbose' => sub { $Verbose++ },
  '--preserve-info-file' => \$PreserveInfoFile,
  '--dump-info-file-before-die' => \$DumpInfoFileBeforeDie,
  '--execute-system-package-installer' => \$ExecuteSystemPackageInstaller,

  '--install-module=s' => sub {
    my $module = PMBP::Module->new_from_module_arg ($_[1]);
    push @Command, {type => 'install-module', module => $module};
  },
  '--install-modules-by-file-name=s' => sub {
    push @Command, {type => 'install-modules-by-list', file_name => $_[1]};
  },
  '--install-modules-by-list' => sub {
    push @Command, {type => 'install-modules-by-list'};
  },
  '--install-to-pmpp=s' => sub {
    my $module = PMBP::Module->new_from_module_arg ($_[1]);
    push @Command, {type => 'install-to-pmpp', module => $module};
  },
  '--install-by-pmpp' => sub {
    push @Command, {type => 'install-by-pmpp'};
  },
  '--update-pmpp-by-file-name=s' => sub {
    push @Command, {type => 'update-pmpp-by-list', file_name => $_[1]};
  },
  '--update-pmpp-by-list' => sub {
    push @Command, {type => 'update-pmpp-by-list'};
  },
  '--scandeps=s' => sub {
    my $module = PMBP::Module->new_from_module_arg ($_[1]);
    push @Command, {type => 'scandeps', module => $module};
  },
  '--select-module=s' => sub {
    my $module = PMBP::Module->new_from_module_arg ($_[1]);
    push @Command, {type => 'select-module', module => $module};
  },
  '--select-modules-by-file-name=s' => sub {
    push @Command, {type => 'select-modules-by-list', file_name => $_[1]};
  },
  '--select-modules-by-list' => sub {
    push @Command, {type => 'select-modules-by-list'};
  },
  '--read-module-index=s' => sub {
    push @Command, {type => 'read-module-index', file_name => $_[1]};
  },
  '--read-carton-lock=s' => sub {
    push @Command, {type => 'read-carton-lock', file_name => $_[1]};
  },
  '--write-module-index=s' => sub {
    push @Command, {type => 'write-module-index', file_name => $_[1]};
  },
  '--write-pmb-install-list=s' => sub {
    push @Command, {type => 'write-pmb-install-list', file_name => $_[1]};
  },
  '--write-install-module-index=s' => sub {
    push @Command, {type => 'write-install-module-index', file_name => $_[1]};
  },
  '--write-libs-txt=s' => sub {
    push @Command, {type => 'write-libs-txt', file_name => $_[1]};
  },
  '--write-makefile-pl=s' => sub {
    push @Command, {type => 'write-makefile-pl', file_name => $_[1]};
  },
  '--print-perl-core-version=s' => sub {
    push @Command, {type => 'print-perl-core-version', module_name => $_[1]};
  },
  '--set-module-index=s' => sub {
    push @Command, {type => 'set-module-index', file_name => $_[1]};
  },
  '--prepend-mirror=s' => sub {
    push @Command, {type => 'prepend-mirror', url => $_[1]};
  },
  '--create-perl-command-shortcut=s' => sub {
    push @Command, {type => 'create-perl-command-shortcut',
                    command => $_[1]};
  },
  '--print-scanned-dependency=s' => sub {
    push @Command, {type => 'print-scanned-dependency',
                    dir_name => $_[1]};
  },
  '--print=s' => sub {
    push @Command, {type => 'print', string => $_[1]};
  },
  (map {
    my $n = $_;
    ("--$n=s" => sub {
      my $module = PMBP::Module->new_from_module_arg ($_[1]);
      push @Command, {type => $n, module => $module};
    });
  } qw(print-module-pathname print-module-version)),
  (map {
    my $n = $_;
    ("--$n" => sub {
      push @Command, {type => $n};
    });
  } qw(
    update install
    install-perl
    print-latest-perl-version
    print-libs print-pmtar-dir-name print-perl-path
  )),
) or die "Usage: $0 options... (See source for details)\n";

# {root}
sub make_path ($);
make_path ($RootDirName);
$RootDirName = abs_path $RootDirName;

# {root}/local/cpanm
my $CPANMDirName = "$RootDirName/local/cpanm";
my $CPANMHomeDirName = "$CPANMDirName/tmp";
my $CPANMCommand = "$CPANMDirName/bin/cpanm";
my $CPANMWrapper = "$CPANMDirName/bin/cpanmwrapper";

# {root}/local/pmbp
my $PMBPDirName = "$RootDirName/local/pmbp";
my $PMBPLogDirName = "$PMBPDirName/logs";

# {root}/deps
$PMTarDirName ||= $RootDirName . '/deps/pmtar';
$PMPPDirName ||= $RootDirName . '/deps/pmpp';
make_path $PMTarDirName;
my $DepsJSONDirName = "$PMTarDirName/deps";

## ------ Logging ------

{
  my $InfoNeedNewline = 0;
  my $InfoFile;
  my $InfoFileName;
  
  sub open_info_file () {
    $InfoFileName = "$PMBPLogDirName/pmbp-" . time . "-" . $$ . ".log";
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
    close $InfoFile;
    if ($DumpInfoFileBeforeDie) {
      open my $info_file, '<', $InfoFileName
          or die "$0: $InfoFileName: $!";
      local $/ = undef;
      print STDERR "\n";
      print STDERR "========== Start - $InfoFileName ==========\n";
      print STDERR <$info_file>;
      print STDERR "========== End - $InfoFileName ==========\n";
      print STDERR "\n";
      die "$0 failed\n";
    } else {
      die "$0 failed; See $InfoFileName for details\n";
    }
  } # info_die

  sub info_writing ($$$) {
    info $_[0], join '', "Writing ", $_[1], " ", File::Spec->abs2rel ($_[2]), " ...";
  } # info_writing

  sub info_end () {
    $InfoNeedNewline--, print STDERR "\n" if $InfoNeedNewline;
  } # info_end
}

## ------ PMBP ------

{
  my $PMBPLibDirName;
  
  sub init_pmbp () {
    $PMBPLibDirName = sprintf '%s/local/perl-%vd/pmbp/self',
        $RootDirName, $^V;
    unshift @INC,
        "$PMBPLibDirName/lib/perl5/$Config{archname}",
        "$PMBPLibDirName/lib/perl5";
  } # init_pmbp
  
  sub install_pmbp_module ($) {
    my $module = shift;
    get_local_copy_if_necessary ($module);
    cpanm ({perl_command => $^X,
            perl_version => (sprintf '%vd', $^V),
            perl_lib_dir_name => $PMBPLibDirName,
            local_option => '-l', skip_satisfied => 1}, [$module]);
  } # install_pmbp_module
}

## ------ Files and directories ------

sub make_path ($) { mkpath $_[0] }
sub remove_tree ($) { rmtree $_[0] }

sub mkdir_for_file ($) {
  my $file_name = $_[0];
  $file_name =~ s{[^/\\]+$}{};
  make_path $file_name;
} # mkdir_for_file

sub copy_log_file ($$) {
  my ($file_name, $module_name) = @_;
  my $log_file_name = $module_name;
  $log_file_name =~ s/::/-/g;
  $log_file_name = "$PMBPLogDirName/@{[time]}-$log_file_name.log";
  mkdir_for_file $log_file_name;
  copy $file_name => $log_file_name or die "Can't save log file: $!\n";
  info_writing 0, "install log file", $log_file_name;
  open my $file, '<', $file_name or die "$0: $file_name: $!";
  local $/ = undef;
  my $content = <$file>;
  info 5, "";
  info 5, "========== Start - $log_file_name ==========";
  info 5, $content;
  info 5, "========== End - $log_file_name ==========";
  info 5, "";
  return $content;
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
  info ((defined $args{info_command_level} ? $args{info_command_level} : 2),
        qq{$prefix\$ @{[map { $_ . '="' . (_quote_dq $envs->{$_}) . '" ' } sort { $a cmp $b } keys %$envs]}@$command});
  local %ENV = (%ENV, %$envs);
  open my $cmd, "-|",
      (join ' ', map quotemeta, @$command) .
      " 2>&1" .
      (defined $args{">"} ? ' > ' . quotemeta $args{">"} : '') .
      ($args{accept_input} ? '' : ' < /dev/null')
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
  run_command [$WgetCommand, '-O', $_[1], $_[0]], info_level => 2;
  return -f $_[1];
} # _save_url

sub save_url ($$) {
  _save_url (@_) or die "Failed to download <$_[0]>\n";
} # save_url

## ------ JSON ------

{
  my $JSONInstalled;
  
  sub encode_json ($) {
    unless ($JSONInstalled) {
      $JSONInstalled = 1;
      eval q{ require JSON } or
      install_pmbp_module (PMBP::Module->new_from_package ('JSON'));
    }
    require JSON;
    return JSON->new->utf8->allow_blessed->convert_blessed->allow_nonref->pretty->canonical->encode ($_[0]);
  } # encode_json

  sub decode_json ($) {
    unless ($JSONInstalled) {
      $JSONInstalled = 1;
      eval q{ require JSON } or
      install_pmbp_module (PMBP::Module->new_from_package ('JSON'));
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

## ------ System environment ------

{
  my $HasAPT = {};
  my $HasYUM = {};
  sub install_system_packages ($$) {
    my ($perl_version, $packages) = @_;
    return unless @$packages;
    
    $HasAPT->{$perl_version} = which ($AptGetCommand, $perl_version)
        ? 1 : 0 if not defined $HasAPT;
    $HasYUM->{$perl_version} = which ($YumCommand, $perl_version)
        ? 1 : 0 if not defined $HasYUM;

    my $cmd;
    my $env = '';
    if ($HasAPT->{$perl_version}) {
      $cmd = [$SudoCommand, '--', $AptGetCommand, 'install', '-y', map { $_->{debian_name} || $_->{name} } @$packages];
      $env = 'DEBIAN_FRONTEND="noninteractive" ';
    } elsif ($HasYUM->{$perl_version}) {
      $cmd = [$SudoCommand, '--', $YumCommand, 'install', '-y', map { $_->{redhat_name} || $_->{name} } @$packages];
    }

    if ($cmd) {
      if (not $ExecuteSystemPackageInstaller) {
        info 0, "Execute following command and retry:";
        info 0, '  ' . $env . '$ ' . join ' ', @$cmd;
      } else {
        return run_command $cmd,
            info_level => 0,
            info_command_level => 0,
            envs => {DEBIAN_FRONTEND => "noninteractive"},
            accept_input => -t STDIN;
      }
    } else {
      info 0, "Install following packages and retry:";
      info 0, "  " . join ' ', map { $_->{name} } @$packages;
    }
    return 0;
  } # install_system_packages
}

{
  my $EnvPath = {};
  sub get_env_path ($) {
    my $perl_version = shift;
    my $perl_path = "$RootDirName/local/perlbrew/perls/perl-$perl_version/bin";
    my $pm_path = get_pm_dir_name ($perl_version) . "/bin";
    return $EnvPath->{$perl_version} ||= "$pm_path:$perl_path:$ENV{PATH}";
  } # get_env_path

  sub which ($$) {
    my ($command, $perl_version) = @_;
    my $output;
    if (run_command ['which', $command],
            envs => {PATH => get_env_path ($perl_version)},
            onoutput => sub { $output = $_[0]; 3 }) {
      if (defined $output and $output =~ m{^(\S*\Q$command\E)$}) {
        return $1;
      }
    }
    return undef;
  } # which
}

## ------ Perl ------

{
  my $LatestPerlVersion;
  sub get_latest_perl_version () {
    return $LatestPerlVersion if $LatestPerlVersion;

    my $file_name = qq<$PMBPDirName/latest-perl.json>;
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
}

sub get_perl_version ($) {
  my $perl_command = shift;
  my $perl_version;
  run_command [$perl_command, '-e', 'printf "%vd", $^V'],
      onoutput => sub { $perl_version = $_[0]; 2 };
  return $perl_version;
} # get_perl_version

sub init_perl_version ($) {
  my $perl_version = shift || get_perl_version ($PerlCommand) || '';
  $perl_version = get_latest_perl_version if $perl_version eq 'latest';
  $perl_version =~ s/^v//;
  unless ($perl_version =~ /\A5\.[0-9]+\.[0-9]+\z/) {
    info_die "Invalid Perl version: $perl_version\n";
  }
  return $perl_version;
} # init_perl_version

sub get_perlbrew_envs () {
  return {PERLBREW_ROOT => (abs_path "$RootDirName/local/perlbrew")}
} # get_perlbrew_envs

sub install_perlbrew () {
  return if -f "$RootDirName/local/perlbrew/bin/perlbrew";
  save_url $PerlbrewInstallerURL
      => "$RootDirName/local/install.perlbrew";
  run_command
      ['sh', "$RootDirName/local/install.perlbrew"],
      envs => get_perlbrew_envs;
  unless (-f "$RootDirName/local/perlbrew/bin/perlbrew") {
    info_die "Can't install perlbrew";
  }
} # install_perlbrew

sub install_perl ($) {
  my $perl_version = shift;
  install_perlbrew;
  my $i = 0;
  PERLBREW: {
    $i++;
    my $log_file_name;
    my $redo;
    run_command ["$RootDirName/local/perlbrew/bin/perlbrew",
                 'install',
                 'perl-' . $perl_version,
                 '--notest',
                 '--as' => 'perl-' . $perl_version,
                 '-j' => $PerlbrewParallelCount],
                envs => get_perlbrew_envs,
                prefix => "perlbrew($i): ",
                onoutput => sub {
                  if ($_[0] =~ m{^  tail -f (.+?/perlbrew/build.perl-.+?\.log)}) {
                    $log_file_name = $1;
                    $log_file_name =~ s{^~/}{$ENV{HOME}/} if defined $ENV{HOME};
                    return 0;
                  } elsif ($_[0] =~ /^It is possible that the compressed file\(s\) have become corrupted/) {
                    remove_tree "$RootDirName/local/perlbrew/dists";
                    make_path "$RootDirName/local/perlbrew/dists";
                    $redo = 1;
                    return 1;
                  } else {
                    return 1;
                  }
                };
    
    copy_log_file $log_file_name => "perl-$perl_version"
        if defined $log_file_name;
    unless (-f "$RootDirName/local/perlbrew/perls/perl-$perl_version/bin/perl") {
      if ($redo and $i < 10) {
        info 0, "perlbrew($i): Failed to install perl-$perl_version; retrying...";
        redo PERLBREW;
      } else {
        info_die "perlbrew($i): Failed to install perl-$perl_version";
      }
    }
  } # PERLBREW
} # install_perl

sub get_perl_path ($) {
  my $perl_version = shift;
  return which ($PerlCommand, $perl_version)
      || info_die "Can't get path to |perl|";
} # get_perl_path

## ------ cpanm ------

sub install_cpanm () {
  return if -f $CPANMCommand;
  save_url $CPANMURL => $CPANMCommand;
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
  }, $CPANMCommand;
  close $file;
} # install_cpanm_wrapper

{
  my $CPANMDummyHomeDirNames = {};
  sub get_cpanm_dummy_home_dir_name ($) {
    my $lib_dir_name = shift;
    return $CPANMDummyHomeDirNames->{$lib_dir_name} ||= do {
      ## For Module::Build-based packages (e.g. Class::Accessor::Lvalue)
      require Digest::MD5;
      my $key = Digest::MD5::md5_hex ($lib_dir_name);
      my $home_dir_name = "$CPANMHomeDirName/$key";
      my $file_name = "$home_dir_name/.modulebuildrc";
      mkdir_for_file $file_name;
      open my $file, '>', $file_name or die "$0: $file_name: $!";
      print $file "install --install-base $lib_dir_name";
      close $file;
      $home_dir_name;
    };
  } # get_cpanm_dummy_home_dir_name
}

our $CPANMDepth = 0;
my $PerlVersionChecked = {};
sub cpanm ($$);
sub cpanm ($$) {
  my ($args, $modules) = @_;
  my $result = {};
  install_cpanm_wrapper;

  if (not $args->{info} and @$modules == 1 and
      ref $modules->[0] and $modules->[0]->is_perl) {
    info 1, "cpanm invocation for package |perl| skipped";
    return {};
  }

  my $perl_lib_dir_name = $args->{perl_lib_dir_name}
      || ($args->{info} ? $CPANMDirName : undef)
      or die "No |perl_lib_dir_name| specified";
  my $perl_version = $args->{perl_version}
      || ($args->{info} ? (sprintf '%vd', $^V) : undef)
      or die "No |perl_version| specified";
  my $path = get_env_path ($perl_version);
  my $perl_command = $args->{perl_command} || $PerlCommand;

  unless ($PerlVersionChecked->{$path, $perl_version}) {
    my $actual_perl_version = get_perl_version ($perl_command) || '?';
    if ($actual_perl_version eq $perl_version) {
      $PerlVersionChecked->{$path, $perl_version} = 1;
    } else {
      info_die "Perl version mismatch: $actual_perl_version ($perl_version expected)";
    }
  }

  my $redo = 0;
  COMMAND: {
    my @required_cpanm;
    my @required_install;
    my @required_install2;
    my @required_system;

    my $cpanm_lib_dir_name = "$RootDirName/local/perl-$perl_version/cpanm";
    my @perl_option = ("-I$cpanm_lib_dir_name/lib/perl5/$Config{archname}",
                       "-I$cpanm_lib_dir_name/lib/perl5");

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
      ref $_ ? $_->as_cpanm_arg ($PMTarDirName) : $_;
    } @$modules;
    if (grep { not m{/misc/[^/]+\.tar\.gz$} } @module_arg) {
      push @option, '--save-dists' => $PMTarDirName;
    }

    push @option,
        '--mirror' => (abs_path $PMTarDirName),
        map { ('--mirror' => $_) } @CPANMirror;

    if (defined $args->{module_index_file_name} and
        -f $args->{module_index_file_name}) {
      my $mi = abs_path $args->{module_index_file_name};
      push @option, '--mirror-index' => $mi if defined $mi;
    } else {
      get_default_mirror_file_name ();
      unshift @option, '--mirror' => abs_path $CPANMDirName;
    }

    push @option, '--mirror' => abs_path supplemental_module_index ();

    ## Let cpanm not use Web API, as it slows down operations.
    push @option, '--mirror-only';

    my $envs = {LANG => 'C',
                PATH => $path,
                HOME => get_cpanm_dummy_home_dir_name ($perl_lib_dir_name),
                PERL_CPANM_HOME => $CPANMHomeDirName,
               
                ## mod_perl support (incomplete...)
                MP_APXS => $ENV{MP_APXS} || (-f '/usr/sbin/apxs' ? '/usr/sbin/apxs' : undef),
                MP_USE_MY_EXTUTILS_EMBED => 1};

    if (@module_arg and $module_arg[0] eq 'GD') {
      ## <http://bugs.debian.org/cgi-bin/bugreport.cgi?bug=636649>
      $envs->{PERL_MM_OPT} = $ENV{PERL_MM_OPT};
      $envs->{PERL_MM_OPT} = '' unless defined $envs->{PERL_MM_OPT};
      # XXX The following line is wrong
      $envs->{PERL_MM_OPT} .= ' CCFLAGS="-Wformat=0 ' . $Config{ccflags} . '"';
    }

    my $failed;
    my $remove_inc;
    my $install_extutils_embed;
    my $scan_errors; $scan_errors = sub ($$) {
      my ($level, $log) = @_;
      if ($log =~ /Can\'t locate (\S+\.pm) in \@INC/m) {
        my $mod = PMBP::Module->new_from_pm_file_name ($1);
        if (defined $mod->package and $mod->package eq 'ExtUtils::Embed') {
          $install_extutils_embed = 1;
          $failed = 1;
        } elsif ($level == 1) {
          push @required_cpanm, $mod;
        } else {
          push @required_install, $mod;
        }
      } elsif ($log =~ /^Building version-\S+ \.\.\. FAIL/m) {
        push @required_install,
            map { PMBP::Module->new_from_package ($_) }
            qw{ExtUtils::MakeMaker ExtUtils::ParseXS};
      } elsif ($log =~ /^skipping .+\/perl-/m) {
        if (@module_arg and $module_arg[0] eq 'Module::Metadata') {
          push @required_install, PMBP::Module->new_from_module_arg
              ('Module::Metadata=http://search.cpan.org/CPAN/authors/id/A/AP/APEIRON/Module-Metadata-1.000011.tar.gz');
          $failed = 1;
        }
      } elsif ($level == 1 and
               ($log =~ /^! (?:Installing|Configuring) (\S+) failed\. See (.+?) for details\.$/m or
                $log =~ /^! Configure failed for (\S+). See (.+?) for details\.$/m)) {
        my $log = copy_log_file $2 => $1;
        $scan_errors->($level + 1, $log);
        $failed = 1;
      } elsif ($log =~ m{^make(?:\[[0-9]+\])?: .+?ExtUtils/xsubpp}m or
               $log =~ m{^Can\'t open perl script "ExtUtils/xsubpp"}m) {
        push @required_install,
            map { PMBP::Module->new_from_package ($_) }
            qw{ExtUtils::MakeMaker ExtUtils::ParseXS};
      } elsif ($log =~ /^only nested arrays of non-refs are supported at .*?\/ExtUtils\/MakeMaker.pm/m) {
        push @required_install, PMBP::Module->new_from_package ('ExtUtils::MakeMaker');
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
        ## In some environment latest version of Net::SSLeay fails to
        ## compile.  According to Google-sensei |nice| could resolve
        ## the problem but I can't confirm it.  Downgrading to 1.36 or
        ## earlier and installing outside of cpanm succeeded (so some
        ## environment variable set by cpanm affects the building
        ## process?).  (Therefore the line below is incomplete, but I
        ## can no longer reproduce the problem.)
        push @required_install, PMBP::Module->new_from_module_arg
            ('Net::SSLeay~1.36=http://search.cpan.org/CPAN/authors/id/F/FL/FLORA/Net-SSLeay-1.36.tar.gz');
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
      } elsif ($log =~ /^ERROR: proj library not found, where is cs2cs\?/m) {
        push @required_system,
            {name => 'proj-devel', debian_name => 'libproj-dev'};
      } elsif ($log =~ /^! Couldn\'t find module or a distribution (\S+) \(/m) {
        my $mod = {
          'Date::Parse' => 'Date::Parse',
          'Test::Builder::Tester' => 'Test::Simple', # Test-Simple 0.98 < TBT 1.07
        }->{$1};
        push @required_install,
            PMBP::Module->new_from_package ($mod) if $mod;
      }
    }; # $scan_errors

    my @cmd = ($perl_command,
               @perl_option,
               $CPANMWrapper,
               @option,
               @module_arg);
    my $json_temp_file = File::Temp->new;
    my $cpanm_ok = run_command \@cmd,
        envs => $envs,
        info_command_level => $args->{info} ? 2 : 1,
        prefix => "cpanm($CPANMDepth/$redo): ",
        '>' => ($args->{scandeps} || $args->{info} ? $json_temp_file : undef),
        onoutput => sub {
          my $info_level = 1;
          if ($_[0] =~ /^! Couldn\'t find module or a distribution /) {
            $info_level = 0;
          }
          $scan_errors->(1, $_);
          return $info_level;
        };
    info 2, "cpanm done";
    ($cpanm_ok and not $failed) or do {
      unless ($CPANMDepth > 100 or $redo++ > 10) {
        my $redo;
        if ($remove_inc and
            @module_arg and $module_arg[0] =~ m{/} and
            -d "$module_arg[0]/inc") {
          remove_tree "$module_arg[0]/inc";
          $redo = 1;
        }
        if (@required_system) {
          $redo = 1
              if install_system_packages $perl_version, \@required_system;
        }
        if ($install_extutils_embed) {
          ## ExtUtils::Embed is core module since 5.003_07 and you
          ## should have the module installed.  Newer versions of the
          ## module is not distributed at CPAN.  Nevertheless, on some
          ## system the module is not installed...
          my $pm = "$perl_lib_dir_name/lib/perl5/ExtUtils/Embed.pm";
          save_url q<http://perl5.git.perl.org/perl.git/blob_plain/HEAD:/lib/ExtUtils/Embed.pm> => $pm;
          undef $install_extutils_embed;
          $redo = 1;
        }
        if (@required_cpanm) {
          local $CPANMDepth = $CPANMDepth + 1;
          for my $module (@required_cpanm) {
            get_local_copy_if_necessary ($module);
            cpanm {perl_version => $perl_version,
                   perl_lib_dir_name => $cpanm_lib_dir_name,
                   local_option => '-l', skip_satisfied => 1}, [$module];
          }
          $redo = 1;
        } elsif (@required_install) {
          if ($perl_lib_dir_name ne $cpanm_lib_dir_name) {
            local $CPANMDepth = $CPANMDepth + 1;
            for my $module (@required_install) {
              if ($args->{scandeps}) {
                scandeps ($args->{scandeps}->{module_index},
                          $perl_version, $module,
                          skip_if_found => 1,
                          module_index_file_name => $args->{module_index_file_name});
                push @{$result->{additional_deps} ||= []}, $module;
              }
              cpanm ({perl_version => $perl_version,
                      perl_lib_dir_name => $perl_lib_dir_name,
                      module_index_file_name => $args->{module_index_file_name}}, [$module])
                  unless $args->{no_install};
            }
            $redo = 1 unless $args->{no_install};
          } else {
            local $CPANMDepth = $CPANMDepth + 1;
            for my $module (@required_install) {
              cpanm ({perl_version => $perl_version,
                      perl_lib_dir_name => $perl_lib_dir_name,
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
  remove_tree $CPANMHomeDirName;
} # destroy_cpanm_home

## ------ Module repositories ------

sub get_default_mirror_file_name () {
  my $file_name = qq<$CPANMDirName/modules/02packages.details.txt.gz>;
  if (not -f $file_name or
      [stat $file_name]->[9] + 24 * 60 * 60 < time or
      [stat $file_name]->[7] < 1 * 1024 * 1024) {
    save_url q<http://ftp.jaist.ac.jp/pub/CPAN/modules/02packages.details.txt.gz> => $file_name;
    utime time, time, $file_name;
  }
  return abs_path $file_name;
} # get_default_mirror_file_name

sub supplemental_module_index () {
  my $dir_name = "$PMBPDirName/supplemental";
  my $file_name = "$dir_name/modules/02packages.details.txt";
  return $dir_name if -f ($file_name . '.gz') and
      [stat ($file_name . '.gz')]->[9] + 24 * 60 * 60 > time;
  my $index =  PMBP::ModuleIndex->new_from_arrayref ([
    PMBP::Module->new_from_module_arg ('ExtUtils::MakeMaker~6.6302=http://search.cpan.org/CPAN/authors/id/M/MS/MSCHWERN/ExtUtils-MakeMaker-6.63_02.tar.gz'),
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
    $path = "$PMTarDirName/authors/id/$path";
    if (not -f $path) {
      save_url $url => $path;
    }
  }
} # get_local_copy_if_necessary

sub save_by_pathname ($$) {
  my ($pathname => $module) = @_;

  my $dest_file_name = "$PMTarDirName/authors/id/$pathname";
  if (-f $dest_file_name) {
    $module->{url} = 'file://' . abs_path "$PMTarDirName/authors/id/$pathname";
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

## ------ pmtar and pmpp repositories ------

sub init_pmtar_git () {
  return if -f "$PMTarDirName/.git/config";
  run_command ['sh', '-c', "cd \Q$PMTarDirName\E && git init"];
} # init_pmtar_git

sub init_pmpp_git () {
  return if -f "$PMPPDirName/.git/config";
  make_path $PMPPDirName;
  run_command ['sh', '-c', "cd \Q$PMPPDirName\E && git init"];
} # init_pmpp_git

sub copy_pmpp_modules ($) {
  my $perl_version = shift;
  return unless -d $PMPPDirName;
  delete_pmpp_arch_dir ();
  require File::Find;
  my $from_base_path = abs_path $PMPPDirName;
  my $to_base_path = get_pm_dir_name ($perl_version);
  make_path $to_base_path;
  $to_base_path = abs_path $to_base_path;
  for my $dir_name ("$PMPPDirName/bin", "$PMPPDirName/lib") {
    next unless -d $dir_name;
    my $rewrite_shebang = $dir_name =~ /bin$/;
    my $perl_path = get_perl_path $perl_version;
    File::Find::find (sub {
      my $rel = File::Spec->abs2rel ((abs_path $_), $from_base_path);
      my $dest = File::Spec->rel2abs ($rel, $to_base_path);
      if (-f $_) {
        info 2, "Copying file $rel...";
        unlink $dest if -f $dest;
        if ($rewrite_shebang) {
          local $/ = undef;
          open my $old_file, '<', $_ or die "$0: $_: $!";
          my $content = <$old_file>;
          $content =~ s{^#!.*?perl[0-9.]*(?:$|(?=\s))}{#!$perl_path};
          open my $new_file, '>', $dest or die "$0: $dest: $!";
          binmode $new_file;
          print $new_file $content;
          close $new_file;
        } else {
          copy $_ => $dest or die "$0: $dest: $!";
        }
        chmod ((stat $_)[2], $dest);
      } elsif (-d $_) {
        info 2, "Copying directory $rel...";
        make_path $dest;
        chmod ((stat $_)[2], $dest);
      }
    }, $dir_name);
  }
} # copy_pmpp_modules

sub delete_pmpp_arch_dir () {
  info 1, "rm -fr $PMPPDirName/lib/perl5/$Config{archname}";
  remove_tree "$PMPPDirName/lib/perl5/$Config{archname}";
} # delete_pmpp_arch_dir

## ------ Local Perl module directories ------

sub get_pm_dir_name ($) {
  my $perl_version = shift;
  return "$RootDirName/local/perl-$perl_version/pm";
} # get_pm_dir_name

sub get_lib_dir_names ($) {
  my $perl_version = shift;
  my $pm_dir_name = get_pm_dir_name ($perl_version);
  my @lib = grep { defined } map { abs_path $_ } map { glob $_ }
      qq{$RootDirName/lib},
      qq{$RootDirName/modules/*/lib},
      qq{$RootDirName/local/submodules/*/lib},
      qq{$pm_dir_name/lib/perl5/$Config{archname}},
      qq{$pm_dir_name/lib/perl5};
  return @lib;
} # get_lib_dir_names

sub get_libs_txt_file_name ($) {
  my $perl_version = shift;
  return "$RootDirName/local/config/perl/libs-$perl_version-$Config{archname}.txt";
} # get_libs_txt_file_name

sub create_perl_command_shortcut ($$) {
  my ($perl_version, $command) = @_;
  my $file_name = "$RootDirName/$command";
  info_writing 1, "command shortcut", $file_name;
  open my $file, '>', $file_name or die "$0: $file_name: $!";
  print $file sprintf qq{\#!/bin/sh\nPATH="%s" PERL5LIB="`cat %s 2> /dev/null`" exec %s "\$\@"\n},
      _quote_dq get_env_path ($perl_version),
      _quote_dq get_libs_txt_file_name ($perl_version),
      $command;
  close $file;
  chmod 0755, $file_name or die "$0: $file_name: $!";
} # create_perl_command_shortcut

## ------ Perl module dependency detection ------

sub scandeps ($$$;%) {
  my ($module_index, $perl_version, $module, %args) = @_;

  if ($args{skip_if_found}) {
    my $module_in_index = $module_index->find_by_module ($module);
    if ($module_in_index) {
      my $name = $module_in_index->distvname;
      if (defined $name) {
        my $json_file_name = "$DepsJSONDirName/$name.json";
        return if -f $json_file_name;
      }
    }
  }

  my $temp_dir = $args{temp_dir} || File::Temp->newdir;

  get_local_copy_if_necessary $module;
  my $result = cpanm {perl_version => $perl_version,
                      perl_lib_dir_name => $temp_dir->dirname,
                      temp_dir => $temp_dir,
                      module_index_file_name => $args{module_index_file_name},
                      scandeps => {module_index => $module_index}}, [$module];

  _scandeps_write_result ($result, $module, $module_index);
} # scandeps

sub _scandeps_write_result ($$$;%) {
  my ($result, $module, $module_index, %args) = @_;

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

  make_path $DepsJSONDirName;
  for my $m (@$result) {
    next unless defined $m->[0]->distvname;
    my $file_name = $DepsJSONDirName . '/' . $m->[0]->distvname . '.json';
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
    $args{onadd}->($m->[0]) if $args{onadd};
  }
  $module_index->merge_modules ([map { $_->[0] } @$result]);
} # _scandeps_write_result

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
    my $json_file_name = "$DepsJSONDirName/$dist.json";
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

## ------ Perl module lists ------

sub select_module ($$$$;%) {
  my ($src_module_index => $perl_version, $module => $dest_module_index, %args) = @_;
  
  my $mods = load_deps $src_module_index => $module;
  unless ($mods) {
    info 0, "Scanning dependency of @{[$module->as_short]}...";
    scandeps $src_module_index, $perl_version, $module, %args;
    $mods = load_deps $src_module_index => $module;
    unless ($mods) {
      if ($module->is_perl) {
        $mods = [];
      } elsif (defined $module->pathname) {
        if (save_by_pathname $module->pathname => $module) {
          scandeps $src_module_index, $perl_version, $module, %args;
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
              scandeps $src_module_index, $module, $perl_version, %args;
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
      $args{onadd}->($module) if $args{onadd};
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

sub read_carton_lock ($$;%) {
  my ($file_name => $module_index, %args) = @_;
  my $json = load_json $file_name;
  my $modules = [];
  for (values %{$json->{modules}}) {
    my $module = PMBP::Module->new_from_carton_lock_entry ($_);
    push @$modules, $module;
    $args{onadd}->($module) if $args{onadd};
  }
  $module_index->merge_modules ($modules);
} # read_carton_lock

## ------ Perl application dependency detection ------

sub read_install_list ($$$;%);
sub read_install_list ($$$;%) {
  my ($dir_name => $module_index, $perl_version, %args) = @_;

  my $onadd = sub { my $source = shift; return sub {
    info 1, sprintf '%s requires %s', $source, $_[0]->as_short;
  } }; # $onadd

  THIS: {
    ## pmb install list format
    my @file = map { (glob "$_/config/perl/modules*.txt") } $dir_name;
    if (@file) {
      for my $file_name (@file) {
        read_pmb_install_list $file_name => $module_index,
            onadd => $onadd->($file_name);
      }
      last THIS;
    }

    ## carton.lock
    my $file_name = "$dir_name/carton.lock";
    if (-f $file_name) {
      read_carton_lock $file_name => $module_index,
          onadd => $onadd->($file_name);
      last THIS;
    }

    ## cpanfile
    if (-f "$dir_name/cpanfile") {
      ## At the time of writing, cpanm can't be used to obtain list of
      ## required modules from cpanfile (though it does support
      ## cpanfile for module installation).
      get_dependency_from_cpanfile
          ("$dir_name/cpanfile" => $module_index,
           onadd => $onadd->("$dir_name/cpanfile"));
      last THIS;
    }
    
    ## CPAN package configuration scripts
    if (-f "$dir_name/Build.PL" or -f "$dir_name/Makefile.PL") {
      my $temp_dir = File::Temp->newdir;
      my $result = cpanm {perl_version => $perl_version,
                          perl_lib_dir_name => $temp_dir->dirname,
                          temp_dir => $temp_dir,
                          scandeps => {module_index => $module_index}},
                         [$dir_name];
      _scandeps_write_result ($result, undef, $module_index,
                              onadd => $onadd->($dir_name));
      last THIS;
    }

    ## From *.pm, *.pl, and *.t
    my $mod_names = scan_dependency_from_directory ($dir_name);
    my $modules = [];
    for (keys %$mod_names) {
      my $mod = PMBP::Module->new_from_package ($_);
      push @$modules, $mod;
      $onadd->($dir_name)->($mod);
    }
    $module_index->merge_modules ($modules);
    last THIS;
  } # THIS

  ## Submodules
  return unless $args{recursive};
  for my $dir_name (map { glob "$dir_name/$_" } qw(
    modules/* t_deps/modules/* local/submodules/*
  )) {
    read_install_list $dir_name => $module_index, $perl_version,
        recursive => $args{recursive} ? $args{recursive} - 1 : 0;
  }
} # read_install_list

sub get_dependency_from_cpanfile ($$;%) {
  my ($file_name => $module_index, %args) = @_;

  install_pmbp_module PMBP::Module->new_from_package ('Module::CPANfile');
  install_pmbp_module PMBP::Module->new_from_package ('CPAN::Meta::Prereqs'); # loaded by Module::CPANfile
  install_pmbp_module PMBP::Module->new_from_package ('CPAN::Meta::Requirements');

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
    my $module = PMBP::Module->new_from_package ($_);
    push @$modules, $module;
    $args{onadd}->($module) if $args{onadd};
  }
  $module_index->merge_modules ($modules);
} # get_dependency_from_cpanfile

sub scan_dependency_from_directory ($) {
  my $dir_name = abs_path shift;

  my $modules = {};

  my @include_dir_name = qw(bin lib script t t_deps);
  my @exclude_pattern = map { "^$_" } qw(modules t_deps/modules t_deps/projects);
  for (split /\n/, qx{cd \Q$dir_name\E && find @{[join ' ', grep quotemeta, @include_dir_name]} 2> /dev/null @{[join ' ', map { "| grep -v $_" } grep quotemeta, @exclude_pattern]} | grep "\\.\\(pm\\|pl\\|t\\)\$" | xargs grep "\\(use\\|require\\) " --no-filename}) {
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
  for (split /\n/, qx{cd \Q$dir_name\E && find @{[join ' ', grep quotemeta, @include_dir_name]} 2> /dev/null | grep "\\.\\(pm\\|pl\\)\$" | xargs grep "package " --no-filename}) {
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

## ------ Perl module installation ------

sub install_module ($$;%) {
  my ($perl_version, $module, %args) = @_;
  get_local_copy_if_necessary $module;
  cpanm {perl_version => $perl_version,
         perl_lib_dir_name => $args{pmpp} ? $PMPPDirName : get_pm_dir_name ($perl_version),
         module_index_file_name => $args{module_index_file_name}},
        [$module];
} # install_module

sub get_module_version ($$) {
  my ($perl_version, $module) = @_;
  my $package = $module->package;
  return undef unless defined $package;
  
  my $result;
  my $return = run_command
      [$PerlCommand, '-M' . $package,
       '-e', sprintf 'print $%s::VERSION', $package],
      envs => {PATH => get_env_path ($perl_version),
               PERL5LIB => (join ':', (get_lib_dir_names ($perl_version)))},
      info_level => 3,
      onoutput => sub {
        $result = $_[0];
        return 3;
      };
  return undef unless $return;
  return $result;
} # get_module_version

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
init_pmbp;
info 6, '$ ' . join ' ', $0, @Argument;
info 6, sprintf '%s %vd (%s)', $^X, $^V, $Config{archname};
info 6, '@INC = ' . join ' ', @INC;
my $perl_version = init_perl_version ($SpecifiedPerlVersion);
info 1, "Target Perl version: $perl_version";

while (@Command) {
  my $command = shift @Command;
  if ($command->{type} eq 'update') {
    my $module_list_file_name = "$RootDirName/deps/pmtar/modules/index.txt";
    my $pmb_install_file_name = "$RootDirName/config/perl/pmb-install.txt";
    unshift @Command,
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
    my $module_list_file_name = "$RootDirName/deps/pmtar/modules/index.txt";
    my $pmb_install_file_name = "$RootDirName/config/perl/pmb-install.txt";
    unshift @Command,
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
    install_perl ($perl_version);

  } elsif ($command->{type} eq 'install-module') {
    delete_pmpp_arch_dir if $pmpp_touched;
    info 0, "Installing @{[$command->{module}->as_short]}...";
    install_module $perl_version, $command->{module},
        module_index_file_name => $module_index_file_name;
  } elsif ($command->{type} eq 'install-modules-by-list') {
    delete_pmpp_arch_dir if $pmpp_touched;
    my $module_index = PMBP::ModuleIndex->new_empty;
    if (defined $command->{file_name}) {
      read_pmb_install_list $command->{file_name} => $module_index;
    } else {
      read_install_list $RootDirName => $module_index, $perl_version,
          recursive => 1;
    }
    for ($module_index->to_list) {
      info 0, "Installing @{[$_->as_short]}...";
      install_module $perl_version, $_,
          module_index_file_name => $module_index_file_name;
    }
  } elsif ($command->{type} eq 'install-to-pmpp') {
    info 0, "Installing @{[$command->{module}->as_short]} to pmpp...";
    install_module $perl_version, $command->{module},
        module_index_file_name => $module_index_file_name, pmpp => 1;
    $pmpp_touched = 1;
  } elsif ($command->{type} eq 'install-by-pmpp') {
    info 0, "Copying pmpp modules...";
    copy_pmpp_modules ($perl_version);
  } elsif ($command->{type} eq 'update-pmpp-by-list') {
    my $module_index = PMBP::ModuleIndex->new_empty;
    if (defined $command->{file_name}) {
      read_pmb_install_list $command->{file_name} => $module_index;
    } else {
      read_install_list $RootDirName => $module_index, $perl_version,
          recursive => 1;
    }
    for ($module_index->to_list) {
      info 0, "Installing @{[$_->as_short]} to pmpp...";
      install_module $perl_version, $_,
          module_index_file_name => $module_index_file_name, pmpp => 1;
    }
    $pmpp_touched = 1;
  } elsif ($command->{type} eq 'scandeps') {
    info 0, "Scanning dependency of @{[$command->{module}->as_short]}...";
    scandeps $global_module_index, $perl_version, $command->{module},
        skip_if_found => 1,
        module_index_file_name => $module_index_file_name;
  } elsif ($command->{type} eq 'select-module') {
    select_module $global_module_index =>
        $perl_version, $command->{module} => $selected_module_index,
        module_index_file_name => $module_index_file_name;
    $global_module_index->merge_module_index ($selected_module_index);
  } elsif ($command->{type} eq 'select-modules-by-list') {
    my $module_index = PMBP::ModuleIndex->new_empty;
    if (defined $command->{file_name}) {
      read_pmb_install_list $command->{file_name} => $module_index;
    } else {
      read_install_list $RootDirName => $module_index, $perl_version,
          recursive => 1;
    }
    select_module $global_module_index =>
        $perl_version, $_ => $selected_module_index,
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
    $file_name = get_libs_txt_file_name ($perl_version)
        unless defined $file_name;
    mkdir_for_file $file_name;
    open my $file, '>', $file_name or die "$0: $file_name: $!";
    info_writing 0, "lib paths", $file_name;
    print $file join ':', (get_lib_dir_names ($perl_version));
  } elsif ($command->{type} eq 'create-libs-txt-symlink') {
    my $real_name = get_libs_txt_file_name ($perl_version);
    my $link_name = "$RootDirName/config/perl/libs.txt";
    mkdir_for_file $link_name;
    unlink $link_name or die "$0: $link_name: $!" if -f $link_name;
    symlink $real_name => $link_name or die "$0: $link_name: $!";
  } elsif ($command->{type} eq 'create-perl-command-shortcut') {
    create_perl_command_shortcut $perl_version, $command->{command};
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
    print join ':', (get_lib_dir_names ($perl_version));
  } elsif ($command->{type} eq 'set-module-index') {
    $module_index_file_name = $command->{file_name}; # or undef
  } elsif ($command->{type} eq 'prepend-mirror') {
    if ($command =~ m{^[^/]}) {
      $command->{url} = abs_path $command->{url};
    }
    unshift @CPANMirror, $command->{url};
  } elsif ($command->{type} eq 'print-pmtar-dir-name') {
    print $PMTarDirName;
  } elsif ($command->{type} eq 'init-pmtar-git') {
    init_pmtar_git;
  } elsif ($command->{type} eq 'init-pmpp-git') {
    init_pmpp_git;
  } elsif ($command->{type} eq 'print-scanned-dependency') {
    my $mod_names = scan_dependency_from_directory $command->{dir_name};
    print map { $_ . "\n" } sort { $a cmp $b } keys %$mod_names;
  } elsif ($command->{type} eq 'print-perl-core-version') {
    install_pmbp_module PMBP::Module->new_from_package ('Module::CoreList');
    require Module::CoreList;
    print Module::CoreList->first_release ($command->{module_name});
  } elsif ($command->{type} eq 'print-module-pathname') {
    my $pathname = $command->{module}->pathname;
    print $pathname if defined $pathname;
  } elsif ($command->{type} eq 'print-module-version') {
    my $ver = get_module_version $perl_version, $command->{module};
    print $ver if defined $ver;
  } elsif ($command->{type} eq 'print-perl-path') {
    print get_perl_path ($perl_version);
  } elsif ($command->{type} eq 'print') {
    print $command->{string};
  } else {
    die "Command |$command->{type}| is not defined";
  }
} # while @Command

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

=item --perl-command="perl"

Specify the path to the C<perl> command used by the script.  If this
option is not specified, the C<perl> command in the default search
path (determined by the C<PATH> environment variable and the
C<--perl-version> option) is used.

=item --perl-version="5.n.m"

Specify the Perl version in use.  If the C<--install-perl> command is
invoked, then the value must be one of Perl versions.  Otherwise, it
must match the version of the default C<perl> command.  If this option
is not specified, the version of the default C<perl> command is used.
The default C<perl> command is determined by the C<--perl-command>
option.

Perl version string C<latest> represents the latest stable version of
Perl.

=item --wget-command="wget"

Specify the path to the "wget" command used to download files from the
Internet.  If this option is not specified, the C<wget> command in the
current C<PATH> is used.

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

The C<sudo> command would ask you to input the password if the
standard input of the script is connected to tty.  Otherwise the
C<sudo> command would fail (unless your password is the empty string
or you are the root).  Installer are executed with options to disable
any prompt.

=item --sudo-command="path/to/sudo"

Specify the path to the C<sudo> command.  If this option is not
specified, the C<sudo> command in the default search path is used.

=item --apt-get-command="path/to/apt-get"

Specify the path to the C<apt-get> command.  If this option is not
specified, the C<apt-get> command in the default search path is used.

=item --yum-command="path/to/yum"

Specify the path to the C<yum> command.  If this option is not
specified, the C<yum> command in the default search path is used.

=item --perlbrew-installer-url="URL"

Specify the URL of the perlbrew installer.  The default URL is
C<http://install.perlbrew.pl/>.

=item --perlbrew-parallel-count="integer"

Specify the number of parallel processes of perlbrew (used for the
C<-j> option to the C<perlbrew>'s C<install> command).

=back

=head2 Options for progress and logs

=over 4

=item --verbose

Increase the level of verbosity by one.  This option can be specified
multiple times.  By default the verbosity level is zero (0).  In this
default mode, only most useful progress messages are printed to the
standard error output.  If the verbosity level is two (2) or greater,
the C<cpanm> command is also invoked with the C<---verbose> option
specifed.

The verbosity level can also be specified as integer by the
C<PMBP_VERBOSE> environment variable.  If both the environment
variable and C<--verbose> option(s) are specified, the effective
verbosity level is C<PMBP_VERBOSE> increased by the number of
C<--verbose> options.

=item --preserve-info-file

If the option is specified, the "info file", i.e. the log file to
which progress and any output from underlying C<perlbrew> and C<cpanm>
commands are written is I<not> deleted even when the processing by the
script has ended successfully.  If the option is not specified, the
file is deleted when the processing has been succeeded.

=item --dump-info-file-before-die

If the option is specified or the C<TRAVIS> environment variable is
set to a true value, the content of the "info file" is printed to the
standard error output before the script aborts due to some error.
This option is particularly useful if you don't have access to the
info file but you does have access to the output of the script
(e.g. in some CI environment).

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

=item --print-perl-path

Print the absolute path to the C<perl> command to be used for
installation and other commands.  Please note that this command should
not be invoked before C<--install-perl> command as its value could be
different between before and after the C<--install-perl> execution.

=item --create-perl-command-shortcut="command-name"

Create a shell script to invoke a command with environement variables
C<PATH> and C<PERL5LIB> set to appropriate values for any locally
installed Perl and its modules under the "root" directory.

For example, by invoking the following command:

  $ perl path/to/pmbp.pl --install \
        --create-perl-command-shortcut perl \
        --create-perl-command-shortcut prove

... then two executable files C<perl> and C<prove> are created.
Therefore,

  $ ./perl bin/myapp.pl
  $ ./prove t/mymodule-*.t

... would run C<perl> and C<prove> installed by the pmbp script with
any Perl modules installed by the pmbp script.

=item --print-perl-core-version="Perl::Module::Name"

Print the first version of Perl where the specified module is bundled
as a core module, as returned by L<Module::CoreList>.  For example,
C<5.007003> is printed if the module specified is C<Encode>.  The
L<Module::CoreList> module is automatically installed for the script
if not available.  If the specified module is not part of core Perl
distribution, nothing is printed.

=item --print-module-version="Perl::Module::Name"

Print the version of the specified module, if installed.  If the
specified module is not installed, nothing is printed.

The version of the module is extracted from the module by C<use>ing
the module and then accessing to the C<$VERSION> variable in the
package of the module.

=item --print="string"

Print the string.  Any string can be specified as the argument.  This
command might be useful to combine multiple C<--print-*> commands.

=back

=head1 ENVIRONMENT VARIABLES

=over 4

=item PMBP_VERBOSE

Set the default verbosity level.  See C<--verbose> option for details.

=item TRAVIS

The C<TRAVIS> environment variable affects log level.  Additionally,
the C<TRAVIS> environment variable enables automatical installation of
Debian apt packages, if required.  See description for related options
for more information.

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
