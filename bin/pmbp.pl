=head1 NAME

pmbp.pl - Perl application environment manager

=cut

use strict;
use warnings;
use Config;
use Cwd qw(abs_path);
use File::Path qw(mkpath rmtree);
use File::Copy qw(copy move);
use File::Temp qw(tempdir);
use File::Spec ();
use Getopt::Long;

my $PerlCommand = 'perl';
my $SpecifiedPerlVersion = $ENV{PMBP_PERL_VERSION};
my $WgetCommand = 'wget';
my $SudoCommand = 'sudo';
my $AptGetCommand = 'apt-get';
my $YumCommand = 'yum';
my $BrewCommand = 'brew';
my $DownloadRetryCount = 2;
my $PerlbrewInstallerURL = q<http://install.perlbrew.pl/>;
my $PerlbrewParallelCount = $ENV{PMBP_PARALLEL_COUNT} || ($ENV{TRAVIS} ? 4 : 1);
my $CPANModuleIndexURL = q<http://search.cpan.org/CPAN/modules/02packages.details.txt.gz>;
my $CPANMURL = q<http://cpanmin.us/>;
my $PMBPURL = q<https://github.com/wakaba/perl-setupenv/raw/master/bin/pmbp.pl>;
my $ImageMagickURL = q<http://www.imagemagick.org/download/ImageMagick.tar.gz>;
my $RootDirName = '.';
my $FallbackPMTarDirName = $ENV{PMBP_FALLBACK_PMTAR_DIR_NAME};
my $PMTarDirName = $ENV{PMBP_PMTAR_DIR_NAME};
my $PMPPDirName = $ENV{PMBP_PMPP_DIR_NAME};
my @Command;
my @CPANMirror = qw(
  http://search.cpan.org/CPAN
  http://cpan.metacpan.org/
  http://backpan.perl.org/
);
my $Verbose = $ENV{PMBP_VERBOSE} || 0;
my $PreserveInfoFile = 0;
my $DumpInfoFileBeforeDie = $ENV{PMBP_DUMP_BEFORE_DIE} || $ENV{TRAVIS} || 0;
my $ExecuteSystemPackageInstaller = $ENV{TRAVIS} || 0;
my $MeCabCharset;
my $HelpLevel;

my @Argument = @ARGV;

GetOptions (
  '--perl-command=s' => sub { $PerlCommand = split /\s+/, $_[1] },
  '--wget-command=s' => sub { $WgetCommand = split /\s+/, $_[1] },
  '--sudo-command=s' => sub { $SudoCommand = split /\s+/, $_[1] },
  '--apt-get-command=s' => sub { $AptGetCommand = split /\s+/, $_[1] },
  '--yum-command=s' => sub { $YumCommand = split /\s+/, $_[1] },
  '--brew-command=s' => sub { $BrewCommand = split /\s+/, $_[1] },
  '--download-retry-count=s' => \$DownloadRetryCount,
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
  '--mecab-charset' => \$MeCabCharset,

  '--help' => sub { $HelpLevel = 1 },
  '--version' => sub { $HelpLevel = {-verbose => 99, -sections => [qw(NAME AUTHOR LICENSE)]} },

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
  '--add-to-gitignore=s' => sub {
    push @Command, {type => 'add-to-gitignore', value => $_[1]};
  },
  '--create-perl-command-shortcut=s' => sub {
    push @Command, {type => 'write-libs-txt'},
                   {type => 'create-perl-command-shortcut', command => $_[1]};
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
      push @Command, {type => $n, value => $_[1]};
    });
  } qw(install-apache)),
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
    update-pmbp-pl print-pmbp-pl-etag
    install-perl print-latest-perl-version print-selected-perl-version
    print-perl-archname print-libs
    print-pmtar-dir-name print-pmpp-dir-name print-perl-path
    install-mecab
  )),
) or do {
  $HelpLevel = 2;
};

if ($HelpLevel) {
  require Pod::Usage;
  Pod::Usage::pod2usage ($HelpLevel);
}

# {root}
sub make_path ($);
make_path ($RootDirName);
$RootDirName = abs_path $RootDirName;

# {root}/local/cpanm
my $CPANMDirName = "$RootDirName/local/cpanm";
my $CPANMHomeDirName = "$CPANMDirName/tmp";
my $CPANMCommand = "$CPANMDirName/bin/cpanm";
my $CPANMWrapper = "$CPANMDirName/bin/cpanmwrapper";
my $MakeInstaller = "$CPANMDirName/bin/makeinstaller";

# {root}/local/pmbp
my $PMBPDirName = "$RootDirName/local/pmbp";
my $PMBPLogDirName = "$PMBPDirName/logs";

# {root}/deps
$PMTarDirName ||= $RootDirName . '/deps/pmtar';
$PMPPDirName ||= $RootDirName . '/deps/pmpp';

## ------ Logging ------

{
  my $InfoNeedNewline = 0;
  my $InfoFile;
  my $InfoFileName;
  
  sub open_info_file () {
    $InfoFileName = "$PMBPLogDirName/pmbp-" . time . "-" . $$ . ".log";
    mkdir_for_file ($InfoFileName);
    open $InfoFile, '>', $InfoFileName or die "$0: $InfoFileName: $!";
    $InfoFile->autoflush (1);
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
    my (undef, $error_file_name, $error_line, $error_sub) = caller 1;
    my $location = "at $error_file_name line $error_line = $error_sub";
    print $InfoFile $_[0] =~ /\n\z/ ? $_[0] : "$_[0]\n";
    print $InfoFile "($location)\n";
    print STDERR $_[0] =~ /\n\z/ ? $_[0] : "$_[0]\n";
    print STDERR "($location)\n";
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
  
  my $PMBPModuleInstalled = {};
  sub install_pmbp_module ($) {
    my $module = shift;
    if (defined $module->package) {
      return if $PMBPModuleInstalled->{$module->package};
      $PMBPModuleInstalled->{$module->package} = 1;
    }
    get_local_copy_if_necessary ($module);
    cpanm ({perl_command => $^X,
            perl_version => (sprintf '%vd', $^V),
            perl_lib_dir_name => $PMBPLibDirName,
            skip_satisfied => 1}, [$module]);
  } # install_pmbp_module
}

sub get_pmbp_pl_etag () {
  our $PMBPHTTPHeader;
  my $etag;
  if (defined $PMBPHTTPHeader and 
      $PMBPHTTPHeader =~ /^ETag: (\S+)/m) {
    $etag = $1;
  }
  return $etag;
} # get_pmbp_pl_etag

sub update_pmbp_pl () {
  my $pmbp_pl_file_name = "$RootDirName/local/bin/pmbp.pl";
  my $etag;
  if (-f $pmbp_pl_file_name) {
    run_command 
        ([$PerlCommand, $pmbp_pl_file_name, '--print-pmbp-pl-etag'],
         discard_stderr => 1,
         onoutput => sub { $etag = $_[0]; 5 }) or undef $etag;
  }

  my $temp_file_name = "$PMBPDirName/tmp/pmbp.pl.http";
  _save_url ($PMBPURL => $temp_file_name,
             save_response_headers => 1,
             ($etag ? (request_headers => [['If-None-Match' => $etag]]) : ()))
      or return;
  my $temp2_file_name = "$PMBPDirName/tmp/pmbp.pl";
  open my $file, '<', $temp_file_name or
      info_die "$0: $temp_file_name: $!";
  local $/ = undef;
  my $script = scalar <$file>;
  open my $file2, '>', $temp2_file_name or
      info_die "$0: $temp2_file_name: $!";
  print $file2 "our \$PMBPHTTPHeader = <<'=cut';\n\n";
  print $file2 $script;
  close $file2;
  run_command ([$PerlCommand, '-c', $temp2_file_name]) or do {
    info 0, "Updating pmbp.pl failed (syntax error)";
    return;
  };

  info_writing 0, 'latest version of pmbp.pl', $pmbp_pl_file_name;
  mkdir_for_file ($pmbp_pl_file_name);
  copy $temp2_file_name => $pmbp_pl_file_name
      or info_die "$0: $pmbp_pl_file_name: $!";
} # update_pmbp_pl

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
  copy $file_name => $log_file_name or 
      info_die "Can't save log file: $!\n";
  info_writing 0, "install log file", $log_file_name;
  open my $file, '<', $file_name or info_die "$0: $file_name: $!";
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
  no warnings 'uninitialized';
  $s =~ s/\"/\\\"/g;
  return $s;
} # _quote_dq

sub run_command ($;%) {
  my ($command, %args) = @_;
  local $_;
  my $prefix = defined $args{prefix} ? $args{prefix} : '';
  my $prefix0 = '';
  $prefix0 .= (length $prefix ? ':' : '') . $args{chdir} if defined $args{chdir};
  my $envs = $args{envs} || {};
  {
    no warnings 'uninitialized';
    info ((defined $args{info_command_level} ? $args{info_command_level} : 2),
          qq{$prefix$prefix0\$ @{[map { $_ . '="' . (_quote_dq $envs->{$_}) . '" ' } sort { $a cmp $b } keys %$envs]}@$command});
  }
  local %ENV = (%ENV, %$envs);
  open my $cmd, "-|",
      (defined $args{chdir} ? "cd \Q$args{chdir}\E && " : "") .
      (join ' ', map quotemeta, @$command) .
      ($args{discard_stderr} ? " 2> /dev/null" : " 2>&1") .
      (defined $args{">"} ? ' > ' . quotemeta $args{">"} : '') .
      ($args{accept_input} ? '' : ' < /dev/null')
      or info_die "$0: $command->[0]: $!";
  while (<$cmd>) {
    my $level = defined $args{info_level} ? $args{info_level} : 1;
    $level = $args{onoutput}->($_) if $args{onoutput};
    info $level, "$prefix$_";
  }
  return close $cmd;
} # run_command

## ------ Downloading ------

sub _save_url {
  my ($url => $file_name, %args) = @_;
  mkdir_for_file $file_name;
  info 1, "Downloading <$url>...";
  for (0..$DownloadRetryCount) {
    info 1, "Retrying download ($_/$DownloadRetryCount)...";
    my $result = run_command
        [$WgetCommand,
         '-O', $file_name,
         ($args{save_response_headers} ? '--save-headers' : ()),
         (map {
           ('--header' => $_->[0] . ': ' . $_->[1]);
         } @{$args{request_headers} or []}),
         $url],
        info_level => 2,
        prefix => "wget($_/$DownloadRetryCount): ";
    return 1 if $result && -f $file_name;
  }
  return 0;
} # _save_url

sub save_url ($$;%) {
  _save_url (@_) or info_die "Failed to download <$_[0]>\n";
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
    return eval { JSON->new->utf8->allow_blessed->convert_blessed->allow_nonref->pretty->canonical->decode ($_[0]) };
  } # decode_json
}

sub load_json ($) {
  open my $file, '<', $_[0] or info_die "$0: $_[0]: $!";
  local $/ = undef;
  my $json = decode_json (<$file>);
  close $file;
  return $json;
} # load_json

## ------ System environment ------

{
  my $HasAPT;
  my $HasYUM;
  my $HasBrew;
  sub install_system_packages ($) {
    my ($packages) = @_;
    return unless @$packages;
    
    $HasAPT = which ($AptGetCommand) ? 1 : 0
        if not defined $HasAPT;
    $HasYUM = which ($YumCommand) ? 1 : 0
        if not defined $HasYUM;
    $HasBrew = which ($BrewCommand) ? 1 : 0
        if not defined $HasBrew;

    my $cmd;
    my $env = '';
    if ($HasAPT) {
      $cmd = [$SudoCommand, '--', $AptGetCommand, 'install', '-y', map { $_->{debian_name} || $_->{name} } @$packages];
      $env = 'DEBIAN_FRONTEND="noninteractive" ';
    } elsif ($HasYUM) {
      $cmd = [$SudoCommand, '--', $YumCommand, 'install', '-y', map { $_->{redhat_name} || $_->{name} } @$packages];
    } elsif ($HasBrew) {
      $cmd = [$BrewCommand, 'install', map { $_->{homebrew_name} || $_->{name} } @$packages];
    }

    if ($cmd) {
      if (not $ExecuteSystemPackageInstaller) {
        info 0, "Execute following command and retry:";
        info 0, '';
        info 0, '  $ ' . $env . join ' ', @$cmd;
        info 0, '';
        if ($_->{name} eq 'libperl-devel') {
          info 0, '(Instead of installing libperl-devel, you can use --install-perl command)';
        }
      } else {
        return run_command $cmd,
            info_level => 0,
            info_command_level => 0,
            envs => {DEBIAN_FRONTEND => "noninteractive"},
            accept_input => -t STDIN;
      }
    } else {
      info 0, "Install following packages and retry:";
      info 0, '';
      info 0, "  " . join ' ', map { $_->{name} } @$packages;
      info 0, '';
      if ($_->{name} eq 'libperl-devel') {
        info 0, '(Instead of installing libperl-devel, you can use --install-perl command)';
      }
    }
    return 0;
  } # install_system_packages
}

{
  sub get_perlbrew_perl_bin_dir_name ($) {
    my $perl_version = shift;
    return "$RootDirName/local/perlbrew/perls/perl-$perl_version/bin";
  } # get_perlbrew_perl_bin_dir_name

  my $EnvPath = {};
  sub get_env_path ($) {
    my $perl_version = shift;
    my $perl_path = get_perlbrew_perl_bin_dir_name $perl_version;
    my $pm_path = get_pm_dir_name ($perl_version) . "/bin";
    return $EnvPath->{$perl_version} ||= "$pm_path:$perl_path:$ENV{PATH}";
  } # get_env_path

  sub which ($;$) {
    my ($command, $perl_version) = @_;
    my $output;
    if (run_command ['which', $command],
            envs => {defined $perl_version ? (PATH => get_env_path ($perl_version)) : ()},
            discard_stderr => 1,
            onoutput => sub { $output = $_[0]; 3 }) {
      if (defined $output and $output =~ m{^(\S*\Q$command\E)$}) {
        return $1;
      }
    }
    return undef;
  } # which
}

## ------ Git repositories ------

sub read_gitignore ($) {
  my $file_name = shift;
  return undef unless -f $file_name;
  open my $file, '<', $file_name or info_die "$0: $file_name: $!";
  my @ignore = map { chomp; $_ } grep { length } <$file>;
  return \@ignore;
} # read_gitignore

sub write_gitignore ($$) {
  my ($ignores, $file_name) = @_;
  mkdir_for_file $file_name;
  open my $file, '>', $file_name or info_die "$0: $file_name: $!";
  print $file join '', map { $_ . "\n" } @{$ignores or []};
  close $file;
} # write_gitignore

sub add_to_gitignore ($$) {
  my ($ignores, $file_name) = @_;
  my $orig_ignores = read_gitignore $file_name;
  my %found;
  my $new_ignores = [grep { not $found{$_}++ } @{$orig_ignores or []}, @{$ignores or []}];
  write_gitignore $new_ignores => $file_name;
} # add_to_gitignore

sub update_gitignore () {
  my $gitignore_file_name = "$RootDirName/.gitignore";
  add_to_gitignore [qw(
    *~
    /local/
    /perl
    /prove
    /plackup
    /Makefile.setupenv
    /cin
    /config/perl/libs.txt
  )] => $gitignore_file_name;
} # update_gitignore

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
      discard_stderr => 1,
      onoutput => sub { $perl_version = $_[0]; 2 };
  return $perl_version;
} # get_perl_version

sub init_perl_version ($) {
  my $perl_version = shift;
  $perl_version = get_perl_version $PerlCommand if not defined $perl_version;
  $perl_version = '' if not defined $perl_version;
  $perl_version = get_latest_perl_version if $perl_version eq 'latest';
  $perl_version =~ s/^v//;
  unless ($perl_version =~ /\A5\.[0-9]+\.[0-9]+\z/) {
    info_die "Invalid Perl version: $perl_version\n";
  }
  return $perl_version;
} # init_perl_version

sub init_perl_version_by_file_name ($) {
  open my $file, '<', $_[0] or info_die "$0: $_[0]: $!";
  my $version = <$file>;
  $version = '' unless defined $version;
  chomp $version;
  return init_perl_version $version;
} # init_perl_version_by_file_name

sub get_perlbrew_envs () {
  return {PERLBREW_ROOT => (abs_path "$RootDirName/local/perlbrew"),
          PERL5LIB => ''}
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
                 '-j' => $PerlbrewParallelCount,
                 '-A' => 'ccflags=-fPIC',
                 '-D' => 'usethreads'],
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
    my $perl_path = "$RootDirName/local/perlbrew/perls/perl-$perl_version/bin/perl";
    unless (-f $perl_path) {
      if ($redo and $i < 10) {
        info 0, "perlbrew($i): Failed to install perl-$perl_version; retrying...";
        redo PERLBREW;
      } else {
        info_die "perlbrew($i): Failed to install perl-$perl_version";
      }
    }
    $PerlCommand = $perl_path;
  } # PERLBREW
} # install_perl

sub create_perlbrew_perl_latest_symlink ($) {
  my $perl_version = shift;
  install_perlbrew;
  if (-e "$RootDirName/local/perlbrew/perls/perl-latest") {
    run_command ["$RootDirName/local/perlbrew/bin/perlbrew",
                 'alias', 'delete', 'perl-latest'],
                envs => get_perlbrew_envs;
  }
  run_command ["$RootDirName/local/perlbrew/bin/perlbrew",
               'alias', 'create', "perl-$perl_version" => 'perl-latest'],
              envs => get_perlbrew_envs;
} # create_perlbrew_perl_latest_symlink

sub get_perl_path ($) {
  my $perl_version = shift;
  return which ($PerlCommand, $perl_version)
      || info_die "Can't get path to |perl|";
} # get_perl_path

{
  my $PerlVersionChecked = {};
  sub _check_perl_version ($$) {
    my ($perl_command, $perl_version) = @_;
    my $path = get_env_path $perl_version;
    unless ($PerlVersionChecked->{$path, $perl_command}) {
      my $actual_perl_version = get_perl_version ($perl_command) || '?';
      if ($actual_perl_version eq $perl_version) {
        $PerlVersionChecked->{$path} = 1;
      } else {
        info_die "Perl version mismatch: $actual_perl_version ($perl_version expected)" . Carp::longmess ();
      }
    }
  } # _check_perl_version
}

{
  my $PerlConfig = {};
  sub get_perl_config ($$$) {
    my ($perl_command, $perl_version, $key) = @_;
    my $path = get_env_path ($perl_version);
    return $PerlConfig->{$path, $perl_command, $key}
        if $PerlConfig->{$path, $perl_command, $key};

    _check_perl_version $perl_command, $perl_version;
    my $perl_config;
    run_command
        [$perl_command, '-MConfig', '-e', 'print $Config{'.$key.'}'],
        envs => {PATH => $path},
        discard_stderr => 1,
        onoutput => sub { $perl_config = $_[0]; 2 };
    return $PerlConfig->{$path, $perl_command, $key} = $perl_config
        || info_die "Can't get \$Config{$key} of $perl_command";
  } # get_perl_config

  sub get_perl_archname ($$) {
    my ($perl_command, $perl_version) = @_;
    return get_perl_config $perl_command, $perl_version, 'archname';
  } # get_perl_archname
}

## ------ cpanm ------

sub install_cpanm () {
  return if -f $CPANMCommand;
  save_url $CPANMURL => $CPANMCommand;
} # install_cpanm

my $CPANMWrapperCreated;
sub install_cpanm_wrapper () {
  #return if -f $CPANMWrapper;
  return if $CPANMWrapperCreated;
  install_cpanm;
  info_writing 1, "cpanm_wrapper", $CPANMWrapper;
  mkdir_for_file $CPANMWrapper;
  open my $file, '>', $CPANMWrapper or info_die "$0: $CPANMWrapper: $!";
  print $file q{#!/usr/bin/perl
    BEGIN {
      my $file_name = __FILE__;
      $file_name =~ s{[^/\\\\]+$}{};
      $file_name = '.' unless length $file_name;
      require ($file_name . "/cpanm");
    }

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

    my $orig_search_mirror_index_file = \&App::cpanminus::script::search_mirror_index_file;
    *App::cpanminus::script::search_mirror_index_file = sub {
      my $self = shift;
      my ($file, $module, $version) = @_;
      my $value = $orig_search_mirror_index_file->($self, @_);
      return $value if $value;

      open my $fh, '<', $file or return undef;
      my $found;
      while (<$fh>) {
        if (m!^\Q$module\E\s+([\w\.]+)\s+(.*)!m) {
          $found = $self->cpan_module($module, $2, $1);
          last;
        }
      }

      if ($found) {
        if (!$version or
          version->new($found->{module_version} || 0) >= version->new($version)) {
          return $found;
        } else {
          $self->chat("Found $module version $found->{module_version} < $version.\n");
        }
      }
      return undef;
    }; # search_mirror_index_file

    setpgrp 0, 0;
    
    my $app = App::cpanminus::script->new;
    $app->parse_options (@ARGV);
    $app->doit or exit 1;
  };
  close $file;
  $CPANMWrapperCreated = 1;
} # install_cpanm_wrapper

sub install_makeinstaller ($$) {
  my ($name, $makefilepl_args) = @_;
  #return if -f "$MakeInstaller.$name";
  info_writing 1, "makeinstaller.$name", "$MakeInstaller.$name";
  mkdir_for_file "$MakeInstaller.$name";
  open my $file, '>', "$MakeInstaller.$name"
      or info_die "$0: $MakeInstaller.name: $!";
  printf $file q{#!/bin/sh
    (
      export SHELL="%s"
      echo perl Makefile.PL %s && perl Makefile.PL %s && \
      echo make                && make && \
      echo make install        && make install
    ) || echo "!!! MakeInstaller failed !!!"
  }, _quote_dq $ENV{SHELL}, $makefilepl_args, $makefilepl_args;
  close $file;
  chmod 0755, "$MakeInstaller.$name";
} # install_makeinstaller

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
      open my $file, '>', $file_name or info_die "$0: $file_name: $!";
      print $file "install --install-base $lib_dir_name";
      close $file;
      $home_dir_name;
    };
  } # get_cpanm_dummy_home_dir_name
}

our $CPANMDepth = 0;
sub cpanm ($$);
sub cpanm ($$) {
  my ($args, $modules) = @_;
  my $result = {};

  my $perl_lib_dir_name = $args->{perl_lib_dir_name}
      || ($args->{info} ? $CPANMDirName : undef)
      or info_die "No |perl_lib_dir_name| specified";
  my $perl_version = $args->{perl_version}
      || ($args->{info} ? (sprintf '%vd', $^V) : undef)
      or info_die "No |perl_version| specified";
  my $path = get_env_path ($perl_version);
  my $perl_command = $args->{perl_command} || $PerlCommand;

  if (not $args->{info} and @$modules == 1 and ref $modules->[0]) {
    if ($modules->[0]->is_perl) {
      info 1, "cpanm invocation for package |perl| skipped";
      return {};
    }
    my $package = $modules->[0]->package;
    if (defined $package and $package eq 'Image::Magick') {
      build_imagemagick
          ($perl_command, $perl_version, $perl_lib_dir_name,
           module_index_file_name => $args->{module_index_file_name});
    }
  }

  _check_perl_version $perl_command, $perl_version unless $args->{info};
  install_cpanm_wrapper;

  my $archname = $args->{info} ? $Config{archname} : get_perl_archname $perl_command, $perl_version;
  my @additional_path;

  my $redo = 0;
  COMMAND: {
    my @required_cpanm;
    my @required_install;
    my @required_install2;
    my @required_system;
    my %required_misc;

    my $cpanm_lib_dir_name = "$RootDirName/local/perl-$perl_version/cpanm";
    my @perl_option = ("-I$cpanm_lib_dir_name/lib/perl5/$archname",
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
      ref $_ ? $_->as_cpanm_arg (pmtar_dir_name ()) : $_;
    } @$modules;
    if (grep { not m{/misc/[^/]+\.tar\.gz$} } @module_arg) {
      push @option, '--save-dists' => pmtar_dir_name ();
    }

    push @option,
        '--mirror' => pmtar_dir_name (),
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
                PATH => (join ':', @additional_path, $path),
                HOME => get_cpanm_dummy_home_dir_name ($perl_lib_dir_name),
                PERL_CPANM_HOME => $CPANMHomeDirName};
    
    if (@module_arg and $module_arg[0] eq 'GD' and
        not $args->{info} and not $args->{scandeps}) {
      ## <http://bugs.debian.org/cgi-bin/bugreport.cgi?bug=636649>
      install_makeinstaller 'gd', q{CCFLAGS="$PMBP__CCFLAGS"};
      my $ccflags = '-Wformat=0 ' . get_perl_config $perl_command, $perl_version, 'ccflags';
      $envs->{PMBP__CCFLAGS} = $ccflags;
      $envs->{SHELL} = "$MakeInstaller.gd";
      push @option, '--look';
    } elsif (not $args->{info} and not $args->{scandeps} and
             @$modules and
             defined $modules->[0]->distvname and
             $modules->[0]->distvname =~ /^mod_perl-2\./) {
      install_apache_httpd ('2.2');
      ## <http://perl.apache.org/docs/2.0/user/install/install.html#Dynamic_mod_perl>
      install_makeinstaller 'modperl2',
          qq{MP_APXS="$RootDirName/local/apache/httpd-2.2/bin/apxs" } .
          qq{MP_APR_CONFIG="$RootDirName/local/apache/httpd-2.2/bin/apr-1-config"};
      $envs->{SHELL} = "$MakeInstaller.modperl2";
      push @option, '--look';
    } elsif (not $args->{info} and not $args->{scandeps} and
             @$modules and
             defined $modules->[0]->distvname and
             $modules->[0]->distvname =~ /^mod_perl-1\./) {
      install_apache1 ();
      ## <http://perl.apache.org/docs/1.0/guide/getwet.html>
      install_makeinstaller 'modperl1',
          qq{USE_APXS=1 WITH_APXS="$RootDirName/local/apache/httpd-1.3/bin/apxs" EVERYTHING=1};
      $envs->{SHELL} = "$MakeInstaller.modperl1";
      push @option, '--look';
    #} elsif ($args->{scandeps} and
    #         @$modules and
    #         defined $modules->[0]->distvname and
    #         $modules->[0]->distvname =~ /^mod_perl-2\./) {
    #  install_apache_httpd ('2.2');
    #  # XXX This does not work well...
    #} elsif ($args->{scandeps} and
    #         @$modules and
    #         defined $modules->[0]->distvname and
    #         $modules->[0]->distvname =~ /^mod_perl-1\./) {
    #  install_apache1 ();
    #  # XXX This does not work well...
    } elsif (@module_arg and $module_arg[0] eq 'Text::MeCab' and
             not $args->{info} and not $args->{scandeps}) {
      my $mecab_config = mecab_config_file_name ();
      unless (defined $mecab_config) {
        install_mecab ();
        $mecab_config = mecab_config_file_name ();
      }
      # <http://cpansearch.perl.org/src/DMAKI/Text-MeCab-0.20014/tools/probe_mecab.pl>
      install_makeinstaller 'textmecab',
          qq{--mecab-config="$mecab_config" } .
          qq{--encoding="} . mecab_charset () . q{"};
      $envs->{SHELL} = "$MakeInstaller.textmecab";
      $envs->{LD_LIBRARY_PATH} = mecab_lib_dir_name ();
      push @option, '--look';
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
          push @required_install, $mod;
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
        if ($log =~ m{! You might have to install the following modules first to get --scandeps working correctly.\n!((?:\n! \* \S+)+)}) {
          my $modules = $1;
          while ($modules =~ /^! \* (\S+)/mg) {
            push @required_install, PMBP::Module->new_from_package ($1);
          }
        }
        $failed = 1;
      } elsif ($log =~ m{^(\S+) \S+ is required to configure this module; please install it or upgrade your CPAN/CPANPLUS shell.}m) {
        push @required_install, PMBP::Module->new_from_package ($1);
        # Don't set $failed flag.
      } elsif ($log =~ m{^make(?:\[[0-9]+\])?: .+?ExtUtils/xsubpp}m or
               $log =~ m{^Can\'t open perl script ".*?ExtUtils/xsubpp"}m) {
        push @required_install,
            map { PMBP::Module->new_from_package ($_) }
            qw{ExtUtils::MakeMaker ExtUtils::ParseXS};
        $failed = 1;
      } elsif ($log =~ m{Undefined subroutine &ExtUtils::ParseXS::\S+ called}m) {
        push @required_install,
            map { PMBP::Module->new_from_package ($_) }
            qw{ExtUtils::MakeMaker ExtUtils::ParseXS};
        $failed = 1;
      } elsif ($log =~ /^Failed to extract .+.zip - You need to have unzip or Archive::Zip installed./m) {
        push @required_cpanm, PMBP::Module->new_from_package ('Archive::Zip');
      } elsif ($log =~ /^only nested arrays of non-refs are supported at .*?\/ExtUtils\/MakeMaker.pm/m) {
        push @required_install,
            PMBP::Module->new_from_package ('ExtUtils::MakeMaker');
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
      } elsif ($log =~ m{^Can't link/include 'gmp.h', 'gmp'}m) {
        push @required_system,
            {name => 'gmp-devel', debian_name => 'libgmp-dev',
             homebrew_name => 'gmp'};
        $failed = 1;
      } elsif ($log =~ /^Could not find gdlib-config in the search path. Please install libgd /m) {
        push @required_system,
            {name => 'gd-devel', debian_name => 'libgd2-xpm-dev'};
        $failed = 1;
      } elsif ($log =~ m{ld: cannot find -lmysqlclient}m) {
        push @required_system,
            {name => 'mysql-devel', redhat_name => 'MySQL-devel',
             debian_name => 'libmysqld-dev'};
        $failed = 1;
      } elsif ($log =~ /^version.c:.+?: error: db.h: No such file or directory/m and
               $log =~ /^-> FAIL Installing DB_File failed/m) {
        push @required_system,
            {name => 'bdb-devel', redhat_name => 'db-devel',
             debian_name => 'libdb-dev'};
        $failed = 1;
      } elsif ($log =~ m{ld: cannot find -lperl$}m) {
        push @required_system,
            {name => 'perl-devel', debian_name => 'libperl-dev'};
        $failed = 1;
      } elsif ($log =~ /^Expat.xs:.+?: error: expat.h: No such file or directory/m) {
        push @required_system,
            {name => 'expat-devel', debian_name => 'libexpat1-dev'};
        $failed = 1;
      } elsif ($log =~ /^This module requires GNU Libidn, which could not be found./m) {
        push @required_system,
            {name => 'libidn-devel', debian_name => 'libidn11-dev'};
        $failed = 1;
      } elsif ($log =~ /^Can\'t proceed without mecab-config./m) {
        $required_misc{mecab} = 1;
        $failed = 1;
      } elsif ($log =~ /^ERROR: proj library not found, where is cs2cs\?/m) {
        push @required_system,
            {name => 'proj-devel', debian_name => 'libproj-dev'};
        $failed = 1;
      } elsif ($log =~ /^! Couldn\'t find module or a distribution (\S+) \(/m) {
        my $mod = {
          'Date::Parse' => 'Date::Parse',
          'Test::Builder::Tester' => 'Test::Simple', # Test-Simple 0.98 < TBT 1.07
        }->{$1};
        push @required_install,
            PMBP::Module->new_from_package ($mod) if $mod;
      } elsif ($log =~ /^!!! MakeInstaller failed !!!$/m) {
        $failed = 1;
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
          $redo = 1 if install_system_packages \@required_system;
        }
        if ($required_misc{mecab}) {
          if (install_mecab ()) {
            $redo = 1;
          }
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
            cpanm {perl_command => $perl_command,
                   perl_version => $perl_version,
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
              cpanm ({perl_command => $perl_command,
                      perl_version => $perl_version,
                      perl_lib_dir_name => $perl_lib_dir_name,
                      module_index_file_name => $args->{module_index_file_name}}, [$module])
                  unless $args->{no_install};
            }
            $redo = 1 unless $args->{no_install};
          } else {
            local $CPANMDepth = $CPANMDepth + 1;
            for my $module (@required_install) {
              cpanm ({perl_command => $perl_command,
                      perl_version => $perl_version,
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
      open my $file, '<', $json_temp_file->filename or info_die "$0: $!";
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
  my $txt_file_name = qq<$CPANMDirName/modules/02packages.details.txt>;
  my $updated;
  if (not -f $file_name or
      [stat $file_name]->[9] + 24 * 60 * 60 < time or
      [stat $file_name]->[7] < 1 * 1024 * 1024) {
    save_url $CPANModuleIndexURL => $file_name;
    utime time, time, $file_name;
    $updated = 1;
  }
  if ($updated or not -f $txt_file_name) {
    info_writing 2, "decompressed module index", $txt_file_name;
    run_command ['sh', '-c', "zcat \Q$file_name\E > \Q$txt_file_name\E"];
  }
  PMBP::Module->set_module_index_file_name ($txt_file_name);
  return abs_path $file_name;
} # get_default_mirror_file_name

sub supplemental_module_index () {
  my $dir_name = "$PMBPDirName/supplemental";
  my $file_name = "$dir_name/modules/02packages.details.txt";
  return $dir_name if -f ($file_name . '.gz') and
      [stat ($file_name . '.gz')]->[9] + 24 * 60 * 60 > time;
  my $index =  PMBP::ModuleIndex->new_from_arrayref ([
    ## Stupid workaround for cpanm's broken version comparison
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
    $path = pmtar_dir_name () . "/authors/id/$path";
    if (not -f $path) {
      save_url $url => $path;
    }
  }
} # get_local_copy_if_necessary

sub save_by_pathname ($$) {
  my ($pathname => $module) = @_;

  my $dest_file_name = pmtar_dir_name () . "/authors/id/$pathname";
  if (-f $dest_file_name) {
    $module->{url} = 'file://' . pmtar_dir_name () . "/authors/id/$pathname";
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
        copy $mirror => $dest_file_name or
            info_die "$0: Can't copy $mirror";
        $module->{url} = $mirror;
        $module->{pathname} = $pathname;
        return 1;
      }
    }
  }
  
  return 0;
} # save_by_pathname

## ------ pmtar and pmpp repositories ------

{
  my $pmtar_dir_created;
  sub pmtar_dir_name () {
    unless ($pmtar_dir_created) {
      if (not (run_command ['sh', '-c', "cd \Q$PMTarDirName\E"],
                  chdir => $RootDirName) and
          defined $FallbackPMTarDirName and
          -d $FallbackPMTarDirName) {
        $PMTarDirName = abs_path $FallbackPMTarDirName;
      } else {
        run_command
            ['mkdir', '-p', $PMTarDirName],
            chdir => $RootDirName
            or info_die "Can't create $PMTarDirName at $RootDirName";
        run_command
            ['sh', '-c', "cd \Q$PMTarDirName\E && pwd"],
            chdir => $RootDirName,
            discard_stderr => 1,
            onoutput => sub { $PMTarDirName = $_[0]; 4 }
            or info_die "Can't get pmtar directory name";
        chomp $PMTarDirName;
      }
      $pmtar_dir_created = 1;
    }
    return $PMTarDirName;
  } # pmtar_dir_name

  my $pmpp_dir_created;
  sub pmpp_dir_name () {
    unless ($pmpp_dir_created) {
      run_command
          ['mkdir', '-p', $PMPPDirName],
          chdir => $RootDirName
          or info_die "Can't create $PMPPDirName at $RootDirName";
      run_command
          ['sh', '-c', "cd \Q$PMPPDirName\E && pwd"],
          chdir => $RootDirName,
          discard_stderr => 1,
          onoutput => sub { $PMPPDirName = $_[0]; 4 }
          or info_die "Can't get pmpp directory name";
      chomp $PMPPDirName;
      $pmpp_dir_created = 1;
    }
    return $PMPPDirName;
  } # pmpp_dir_name
}

sub deps_json_dir_name () {
  return pmtar_dir_name . "/deps";
} # deps_json_dir_name

sub init_pmtar_git () {
  return if -f (pmtar_dir_name . "/.git/config");
  run_command ['git', 'init'],
      chdir => pmtar_dir_name;
} # init_pmtar_git

sub init_pmpp_git () {
  return if -f (pmpp_dir_name . "/.git/config");
  run_command ['git', 'init'],
      chdir => pmpp_dir_name;
} # init_pmpp_git

sub git_pull_current_or_master ($) {
  my $git_dir_name = shift;
  return 0 unless -f "$git_dir_name/.git/config";
  my $branch = '';
  run_command
      ['git', 'branch'],
      chdir => $git_dir_name,
      discard_stderr => 1,
      onoutput => sub { $branch .= $_[0]; 5 };
  if ($branch =~ /^\* \(no branch\)$/m) {
    run_command
        ['git', 'checkout', 'master'],
        chdir => $git_dir_name
            or return 0;
  }
  return run_command
      ['git', 'pull'],
      chdir => $git_dir_name;
} # git_pull_current_or_master

sub pmtar_git_pull () {
  git_pull_current_or_master pmtar_dir_name;
} # pmtar_git_pull

sub pmpp_git_pull () {
  git_pull_current_or_master pmpp_dir_name;
} # pmpp_git_pull

sub copy_pmpp_modules ($$) {
  my ($perl_command, $perl_version) = @_;
  return unless run_command ['sh', '-c', "cd \Q$PMPPDirName\E"];
  delete_pmpp_arch_dir ($perl_command, $perl_version);

  my $ignores = [map { s{^/}{}; s{/$}{}; $_ } grep { 
    m{^/.+/$};
  } @{read_gitignore (pmpp_dir_name . "/.gitignore") || []}];

  require File::Find;
  my $from_base_path = pmpp_dir_name;
  my $to_base_path = get_pm_dir_name ($perl_version);
  make_path $to_base_path;
  $to_base_path = abs_path $to_base_path;
  for my $dir_name (pmpp_dir_name . "/bin", pmpp_dir_name . "/lib") {
    next unless -d $dir_name;
    my $rewrite_shebang = $dir_name =~ /bin$/;
    my $perl_path = get_perl_path $perl_version;
    File::Find::find (sub {
      my $rel = File::Spec->abs2rel ((abs_path $_), $from_base_path);
      for (@$ignores) {
        return if $rel =~ /^\Q$_\E(?:$|\/)/;
      }
      my $dest = File::Spec->rel2abs ($rel, $to_base_path);
      if (-f $_) {
        info 2, "Copying file $rel...";
        unlink $dest if -f $dest;
        if ($rewrite_shebang) {
          local $/ = undef;
          open my $old_file, '<', $_ or info_die "$0: $_: $!";
          my $content = <$old_file>;
          $content =~ s{^#!.*?perl[0-9.]*(?:$|(?=\s))}{#!$perl_path};
          open my $new_file, '>', $dest or info_die "$0: $dest: $!";
          binmode $new_file;
          print $new_file $content;
          close $new_file;
        } else {
          copy $_ => $dest or info_die "$0: $dest: $!";
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

sub delete_pmpp_arch_dir ($$) {
  my ($perl_command, $perl_version) = @_;
  my $archname = get_perl_archname $perl_command, $perl_version;
  add_to_gitignore ["/lib/perl5/$archname/", '/man/']
      => pmpp_dir_name . "/.gitignore";
} # delete_pmpp_arch_dir

## ------ Local Perl module directories ------

sub get_pm_dir_name ($) {
  my $perl_version = shift;
  return "$RootDirName/local/perl-$perl_version/pm";
} # get_pm_dir_name

sub get_lib_dir_names ($$) {
  my ($perl_command, $perl_version) = @_;
  my $pm_dir_name = get_pm_dir_name ($perl_version);
  my $archname = get_perl_archname $perl_command, $perl_version;
  my @lib = grep { defined } map { abs_path $_ } map { glob $_ }
      qq{$RootDirName/lib},
      qq{$RootDirName/modules/*/lib},
      qq{$RootDirName/local/submodules/*/lib},
      qq{$pm_dir_name/lib/perl5/$archname},
      qq{$pm_dir_name/lib/perl5};
  return @lib;
} # get_lib_dir_names

sub get_libs_txt_file_name ($) {
  my $perl_version = shift;
  return "$RootDirName/local/config/perl/libs-$perl_version-$Config{archname}.txt";
} # get_libs_txt_file_name

sub create_perl_command_shortcut ($$) {
  my ($perl_version, $command) = @_;
  my $file_name = $command =~ m{/} ? $command : "$RootDirName/$command";
  mkdir_for_file $file_name;
  $command = $1 if $command =~ m{/([^/]*)$};
  info_writing 1, "command shortcut", $file_name;
  my $perl_path = get_perlbrew_perl_bin_dir_name $perl_version;
  my $pm_path = get_pm_dir_name ($perl_version) . "/bin";
  open my $file, '>', $file_name or info_die "$0: $file_name: $!";
  print $file sprintf qq{\#!/bin/sh\nPMBP_ORIG_PATH="`perl -e '%s'`" PATH="%s" PERL5LIB="`cat %s 2> /dev/null`" exec %s "\$\@"\n},
      _quote_dq 'print $ENV{PMBP_ORIG_PATH} || $ENV{PATH}',
      _quote_dq "$pm_path:$perl_path:" . '$PATH',
      _quote_dq get_libs_txt_file_name ($perl_version),
      $command;
  close $file;
  chmod 0755, $file_name or info_die "$0: $file_name: $!";
} # create_perl_command_shortcut

## ------ Perl module dependency detection ------

sub scandeps ($$$;%) {
  my ($module_index, $perl_version, $module, %args) = @_;

  if ($args{skip_if_found}) {
    my $module_in_index = $module_index->find_by_module ($module);
    if ($module_in_index) {
      my $name = $module_in_index->distvname;
      if (defined $name) {
        my $json_file_name = deps_json_dir_name . "/$name.json";
        return if -f $json_file_name;
      }
    }
  }

  my $temp_dir_name = $args{temp_dir_name} || tempdir('PMBP-XX'.'XX'.'XX', TMPDIR => 1, CLEANUP => 1);

  get_local_copy_if_necessary $module;
  my $result = cpanm {perl_version => $perl_version,
                      perl_lib_dir_name => $temp_dir_name,
                      temp_dir_name => $temp_dir_name,
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

  my $deps_json_dir_name = deps_json_dir_name;
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
    open my $file, '>', $file_name or info_die "$0: $file_name: $!";
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
    my $json_file_name = deps_json_dir_name . "/$dist.json";
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
          if (defined $path and $path =~ s{-[0-9A-Za-z.+-]+\.(tar\.(?:gz|bz2)|zip|tgz)$}{-@{[$module->version]}.$1}) {
            if (save_by_pathname $path => $module) {
              scandeps $src_module_index, $module, $perl_version, %args;
              $mods = load_deps $src_module_index => $module;
            }
          }
        }
      } # version
      info_die "Can't detect dependency of @{[$module->as_short]}\n"
          unless $mods;
    }
  }
  $dest_module_index->merge_modules ($mods);
} # select_module

sub read_module_index ($$) {
  my ($file_name => $module_index) = @_;
  my $modules = [];
  _read_module_index ($file_name => sub {
    push @$modules, PMBP::Module->new_from_indexable ($_[0]);
  });
  $module_index->merge_modules ($modules);
} # read_module_index

sub _read_module_index ($$) {
  my ($file_name => $code) = @_;
  unless (-f $file_name) {
    info 0, "$file_name not found; skipped\n";
    return;
  }
  info 2, "Reading module index $file_name...";
  open my $file, '<', $file_name or info_die "$0: $file_name: $!";
  my $has_blank_line;
  while (<$file>) {
    if ($has_blank_line and /^(\S+)\s+(\S+)\s+(\S+)/) {
      $code->([$1, $2, $3]);
    } elsif (/^$/) {
      $has_blank_line = 1;
    }
  }
  info 2, "done";
} # _read_module_index

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
  open my $details, '>', $file_name or info_die "$0: $file_name: $!";
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
  open my $file, '<', $file_name or info_die "$0: $file_name: $!";
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
  open my $file, '>', $file_name or info_die "$0: $file_name: $!";
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
      my $temp_dir_name = tempdir('PMBP-XX'.'XX'.'XX', TMPDIR => 1, CLEANUP => 1);
      my $result = cpanm {perl_version => $perl_version,
                          perl_lib_dir_name => $temp_dir_name,
                          temp_dir_name => $temp_dir_name,
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
  for (split /\n/, qx{cd \Q$dir_name\E && find @{[join ' ', grep quotemeta, @include_dir_name]} 2> /dev/null @{[join ' ', map { "| grep -v $_" } grep quotemeta, @exclude_pattern]} | grep "\\.\\(pm\\|pl\\|t\\)\$" | xargs grep "\\(use\\|require\\|extends\\) " --no-filename}) {
    s/\#.*$//;
    if (/\b(?:(?:use|require)\s*(?:base|parent)|extends)\s*(.+)/) {
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

sub install_module ($$$;%) {
  my ($perl_command, $perl_version, $module, %args) = @_;
  get_local_copy_if_necessary $module;
  my $lib_dir_name = $args{pmpp}
      ? pmpp_dir_name : get_pm_dir_name ($perl_version);
  if (has_module ($perl_command, $perl_version, $module, $lib_dir_name)) {
    info 1, "Module @{[$module->as_short]} is already installed; skipped";
    return;
  }
  cpanm {perl_version => $perl_version,
         perl_lib_dir_name => $lib_dir_name,
         module_index_file_name => $args{module_index_file_name}},
        [$module];
} # install_module

sub get_module_version ($$$) {
  my ($perl_command, $perl_version, $module) = @_;
  my $package = $module->package;
  return undef unless defined $package;
  
  my $result;
  my $return = run_command
      [$perl_command, '-M' . $package,
       '-e', sprintf 'print $%s::VERSION', $package],
      envs => {PATH => get_env_path ($perl_version),
               PERL5LIB => (join ':', (get_lib_dir_names ($perl_command, $perl_version)))},
      info_level => 3,
      discard_stderr => 1,
      onoutput => sub {
        $result = $_[0];
        return 3;
      };
  return undef unless $return;
  return $result;
} # get_module_version

sub has_module ($$$$) {
  my ($perl_command, $perl_version, $module, $dir_name) = @_;
  my $package = $module->package;
  return 0 unless defined $package;
  my $version = $module->version;

  my $file_name = $package . '.pm';
  $file_name =~ s{::}{/}g;
  
  my $archname = get_perl_archname $perl_command, $perl_version;
  for (qq{$dir_name/lib/perl5/$archname/$file_name},
       qq{$dir_name/lib/perl5/$file_name}) {
    next unless -f $_;
    return 1 if not defined $version;
    
    install_pmbp_module PMBP::Module->new_from_package ('Module::Metadata');
    install_pmbp_module PMBP::Module->new_from_package ('version');
    require Module::Metadata;
    require version;

    my $meta = Module::Metadata->new_from_file ($_) or next;
    my $actual_version = $meta->version;
    return 1 if $actual_version >= version->new ($version);
  }
  
  return 0;
} # has_module

## ------ ImageMagick ------

sub download_imagemagick () {
  my $imagemagick_file_name = pmtar_dir_name . "/packages/ImageMagick.tar.gz";
  if (not -f "$imagemagick_file_name.updated" or
      [stat "$imagemagick_file_name.updated"]->[9] + 24 * 60 * 60 < time) {
    save_url $ImageMagickURL => $imagemagick_file_name;
    open my $file, '>', "$imagemagick_file_name.updated";
  }
  return $imagemagick_file_name;
} # download_imagemagick

sub build_imagemagick ($$$;%) {
  my ($perl_command, $perl_version, $install_dir_name, %args) = @_;
  my $tar_file_name = download_imagemagick;
  my $container_dir_name = "$PMBPDirName/tmp/" . int rand 100000;
  make_path $container_dir_name;
  run_command
      ['tar', 'zxf', $tar_file_name],
      chdir => $container_dir_name;
  my $dir_name = glob "$container_dir_name/ImageMagick-*";
  info_die "Can't expand $tar_file_name" unless $dir_name;
  run_command
      ['sh', 'configure',
       '--without-perl',
       '--prefix=' . $install_dir_name,
       '--without-lcms2'],
      chdir => $dir_name
          or info_die "ImageMagick ./configure failed";
  run_command
      ['make'],
      chdir => $dir_name
          or info_die "ImageMagick make failed";
  run_command
      ['make', 'install'],
      chdir => $dir_name
          or info_die "ImageMagick make install failed";
  my $perl_make_file_name = "$dir_name/PerlMagick/Makefile.PL";
  for my $name (qw{ExtUtils::MakeMaker ExtUtils::ParseXS}) {
    my $module = PMBP::Module->new_from_package ($name);
    cpanm {perl_version => $perl_version,
           perl_lib_dir_name => $install_dir_name,
           module_index_file_name => $args{module_index_file_name}},
          [$module];
  }
  {
    open my $file, '<', $perl_make_file_name
        or die "$0: $perl_make_file_name: $!";
    local $/ = undef;
    my $make_pl = <$file>;
    $make_pl =~ s{-L../magick/.libs\b}{-L$install_dir_name/lib}g;
    open $file, '>', $perl_make_file_name
        or die "$0: $perl_make_file_name: $!";
    print $file $make_pl;
  }
  my $envs = {PATH => get_env_path ($perl_version),
              PERL5LIB => (join ':', (get_lib_dir_names ($perl_command, $perl_version)))};
  run_command
      [$perl_command, 'Makefile.PL',
       'INSTALL_BASE="' . $install_dir_name . '"'],
      envs => $envs,
      chdir => "$dir_name/PerlMagick"
          or info_die "PerlMagick Makefile.PL failed";
  run_command
      ['make'],
      envs => $envs,
      chdir => "$dir_name/PerlMagick"
          or info_die "PerlMagick make failed";
  run_command
      ['make', 'install'],
      envs => $envs,
      chdir => "$dir_name/PerlMagick"
          or info_die "PerlMagick make install failed";
  remove_tree $container_dir_name;
} # build_imagemagick

## ------ Apache ------

sub get_latest_apr_versions () {
  my $file_name = qq<$PMBPDirName/apr.html>;
  save_url q<http://apr.apache.org/download.cgi> => $file_name
      if not -f $file_name or
         [stat $file_name]->[9] + 24 * 60 * 60 < time;

  my $html;
  {
    open my $file, '<', $file_name or die "$0: $file_name: $!";
    local $/ = undef;
    $html = scalar <$file>;
  }

  my $versions = {'apr' => '1.4.6',
                  'apr-util' => '1.5.1',
                  _mirror => 'http://www.apache.org/dist/'};

  if ($html =~ /APR ([0-9.]+) is the best available version/) {
    $versions->{apr} = $1;
  }
  if ($html =~ /APR-util ([0-9.]+) is the best available version/) {
    $versions->{'apr-util'} = $1;
  }
  if ($html =~ m{The currently selected mirror is <b>(http://[^<]+)</b>.}) {
    $versions->{_mirror} = $1;
  }
  
  return $versions;
} # get_latest_apr_versions

sub get_latest_apache_httpd_versions () {
  my $file_name = qq<$PMBPDirName/apache-httpd.html>;
  save_url q<http://httpd.apache.org/download.cgi> => $file_name
      if not -f $file_name or
         [stat $file_name]->[9] + 24 * 60 * 60 < time;

  my $html;
  {
    open my $file, '<', $file_name or die "$0: $file_name: $!";
    local $/ = undef;
    $html = scalar <$file>;
  }

  my $versions = {httpd => '2.4.3',
                  'httpd-2.4' => '2.4.3',
                  'httpd-2.2' => '2.2.23',
                  'httpd-2.0' => '2.0.64',
                  _mirror => 'http://www.apache.org/dist/'};

  if ($html =~ /: ([0-9.]+) is the best available version/) {
    $versions->{httpd} = $1;
  }
  if ($html =~ /Apache HTTP Server (2.4.[0-9]+) \(httpd\)/) {
    $versions->{'httpd-2.4'} = $1;
  }
  if ($html =~ /Apache HTTP Server (2.2.[0-9]+) \(httpd\)/) {
    $versions->{'httpd-2.2'} = $1;
  }
  if ($html =~ /Apache HTTP Server (2.0.[0-9]+) /) {
    $versions->{'httpd-2.0'} = $1;
  }
  if ($html =~ m{The currently selected mirror is <b>(http://[^<]+)</b>.}) {
    $versions->{_mirror} = $1;
  }
  
  return $versions;
} # get_latest_apache_httpd_versions

sub save_apache_package ($$$) {
  my ($mirror_url => $package_name, $version) = @_;
  my $file_name = pmtar_dir_name . "/packages/apache/$package_name-$version.tar.gz";
  
  my $url_dir_name = {'apr-util' => 'apr'}->{$package_name} || $package_name;
  for my $mirror ($mirror_url,
                  "http://www.apache.org/dist/",
                  "http://archive.apache.org/dist/") {
    next unless defined $mirror;
    last if -s $file_name;
    _save_url "$mirror$url_dir_name/$package_name-$version.tar.gz"
        => $file_name;
  }
  
  info_die "Can't download $package_name $version"
      unless -f $file_name;
} # save_apache_package

sub install_apache_httpd ($) {
  my $ver = shift;
  if ($ver eq '1.3') {
    install_apache1 ();
  } elsif ($ver eq '2.0' or $ver eq '2.2' or $ver eq '2.4') {
    #
  } else {
    info_die "Apache HTTP Server $ver is not supported";
  }

  my $dest_dir_name = "$RootDirName/local/apache/httpd-$ver";

  if (-f "$dest_dir_name/bin/httpd") {
    info 2, "httpd-$ver is already installed";
    return;
  }

  info 0, "Installing httpd-$ver...";

  my $httpd_versions = get_latest_apache_httpd_versions;
  my $httpd_version = $httpd_versions->{"httpd-$ver"};
  my $need_apr = $ver ne '2.0' && $ver ne '2.2';
  my $apr_versions = $need_apr && get_latest_apr_versions;
  my @tarball = (pmtar_dir_name . "/packages/apache/httpd-$httpd_version.tar.gz");
  info 0, "Apache HTTP Server $httpd_version";
  if ($need_apr) {
    info 0, "  with APR $apr_versions->{apr}";
    info 0, "  with APR-util $apr_versions->{'apr-util'}";
    save_apache_package $apr_versions->{_mirror}
        => 'apr', $apr_versions->{apr};
    save_apache_package $apr_versions->{_mirror}
        => 'apr-util', $apr_versions->{'apr-util'};
    unshift @tarball,
        pmtar_dir_name . "/packages/apache/apr-$apr_versions->{apr}.tar.gz",
        pmtar_dir_name . "/packages/apache/apr-util-$apr_versions->{'apr-util'}.tar.gz";
  }
  save_apache_package $httpd_versions->{_mirror}
      => 'httpd', $httpd_version;

  my $container_dir_name = "$PMBPDirName/tmp/" . int rand 100000;
  make_path $container_dir_name;
  for my $tar_file_name (@tarball) {
    run_command ['tar', 'zxf', $tar_file_name],
        chdir => $container_dir_name
        or info_die "Can't expand $tar_file_name";
  }

  my $src_dir_name = "$container_dir_name/httpd-$httpd_version";
  info_die "Can't chdir to the package's root directory ($src_dir_name)"
      unless -d $src_dir_name;

  if ($need_apr) {
    my $apr_dir_name = "$container_dir_name/apr-$apr_versions->{apr}";
    info_die "Can't chdir to the package's root directory ($apr_dir_name)"
        unless -d $apr_dir_name;
    my $apu_dir_name = "$container_dir_name/apr-util-$apr_versions->{'apr-util'}";
    info_die "Can't chdir to the package's root directory ($apu_dir_name)"
        unless -d $apu_dir_name;
    
    run_command ['mv', $apr_dir_name => "$src_dir_name/srclib/apr"]
        or info_die "Can't move $apr_dir_name";
    run_command ['mv', $apu_dir_name => "$src_dir_name/srclib/apr-util"]
        or info_die "Can't move $apu_dir_name";

  }

  {
    my $log = '';
    my $i = 0;
    my $ok = run_command ['bash', 'configure',
                 "--prefix=$dest_dir_name",
                 '--with-included-apr',
                 '--enable-mods-shared=all ssl cache proxy authn_alias mem_cache file_cache charset_lite dav_lock disk_cache'],
        chdir => $src_dir_name,
        onoutput => sub { $log .= $_[0]; 2 };
    last if $ok;

    if ($log =~ m{^configure: error: pcre-config for libpcre not found. PCRE is required and available from http://pcre.org/}m) {
      if (install_system_packages [{name => 'pcre-devel',
                                    debian_name => 'libpcre3-dev'}]) {
        redo if $i++ < 1;
      }
    }
    info_die "Can't configure the package";
  }

  run_command ['make'],
      chdir => $src_dir_name
      or info_die "Can't build the package";
  run_command ['make', 'install'],
      chdir => $src_dir_name
      or info_die "Can't install the package";
  remove_tree $container_dir_name;
} # install_apache_httpd

sub install_apache1 () {
  my $dest_dir_name = "$RootDirName/local/apache/httpd-1.3";
  if (-f "$dest_dir_name/bin/httpd") {
    info 2, "httpd-1.3 is already installed";
    return;
  }

  info 0, "Installing httpd-1.3...";

  my $version = '1.3.42';
  my $tar_file_name = pmtar_dir_name . "/packages/apache/apache_$version.tar.gz";
  my $url = "http://archive.apache.org/dist/httpd/apache_$version.tar.gz";
  save_url $url => $tar_file_name;

  my $container_dir_name = "$PMBPDirName/tmp/" . int rand 100000;
  make_path $container_dir_name;
  run_command ['tar', 'zxf', $tar_file_name],
      chdir => $container_dir_name
      or info_die "Can't expand $tar_file_name";

  my $src_dir_name = "$container_dir_name/apache_$version";
  info_die "Can't chdir to the package's root directory ($src_dir_name)"
      unless -d $src_dir_name;

  ## <http://www.cambus.net/compiling-apache-1.3.x-on-modern-linux-distributions/>
  run_command ['sed', '-i', 's/getline/apache_getline/', 'src/support/htdigest.c'],
      chdir => $src_dir_name;
  run_command ['sed', '-i', 's/getline/apache_getline/', 'src/support/htpasswd.c'],
      chdir => $src_dir_name;
  run_command ['sed', '-i', 's/getline/apache_getline/', 'src/support/logresolve.c'],
      chdir => $src_dir_name;

  run_command ['bash', 'configure',
               "--prefix=$dest_dir_name",
               '--enable-module=so', 
               '--enable-rule=SHARED_CORE',
               '--enable-module=rewrite',
               '--enable-shared=rewrite',
               '--enable-module=proxy',
               '--enable-shared=proxy'],
      chdir => $src_dir_name
      or info_die "Can't configure the package";
  run_command ['make'],
      chdir => $src_dir_name
      or info_die "Can't build the package";
  run_command ['make', 'install'],
      chdir => $src_dir_name
      or info_die "Can't install the package";
  remove_tree $container_dir_name;
} # install_apache1

sub install_tarball ($$$;%) {
  my ($src_url => $package_category => $dest_dir_name, %args) = @_;
  my $name = $args{name};
  if (not $name and $src_url =~ /([0-9A-Za-z_.-]+)\.tar\.gz$/) {
    $name = $1;
  }
  info_die "No package name specified" unless $name;

  if ($args{check} and $args{check}->()) {
    info 2, "Package $1 already installed";
    return 1;
  }

  info 0, "Installing $1...";
  my $tar_file_name = pmtar_dir_name . "/packages/$package_category/$name.tar.gz";
  save_url $src_url => $tar_file_name unless -f $tar_file_name;
  
  my $container_dir_name = "$PMBPDirName/tmp/" . int rand 100000;
  make_path $container_dir_name;
  run_command ['tar', 'zxf', $tar_file_name],
      chdir => $container_dir_name
      or info_die "Can't expand $tar_file_name";
  my $src_dir_name = "$container_dir_name/$name";

  run_command
      ['sh', 'configure',
       "--prefix=$dest_dir_name",
       @{$args{configure_args} or []}],
      chdir => $src_dir_name
          or info_die "$name ./configure failed";
  run_command
      ['make'],
      chdir => $src_dir_name
          or info_die "$name make failed";
  run_command
      ['make', 'install'],
      chdir => $src_dir_name
          or info_die "$name make install failed";

  remove_tree $container_dir_name;

  return $args{check} ? $args{check}->() : 1;
} # install_tarball

## ------ MeCab ------

sub mecab_version () {
  return '0.994';
} # mecab_version

sub mecab_charset () {
  return $MeCabCharset || 'utf-8';
} # mecab_charset

sub mecab_bin_dir_name () {
  return "$RootDirName/local/mecab-@{[mecab_version]}-@{[mecab_charset]}/bin";
} # mecab_bin_dir_name

sub mecab_lib_dir_name () {
  return "$RootDirName/local/mecab-@{[mecab_version]}-@{[mecab_charset]}/lib";
} # mecab_lib_dir_name

sub mecab_config_file_name () {
  my $bin = mecab_bin_dir_name;
  if (-x "$bin/mecab-config") {
    return "$bin/mecab-config";
  } else {
    return which 'mecab-config';
  }
} # mecab_config_file_name

sub install_mecab () {
  my $mecab_charset = mecab_charset;
  my $mecab_version = '0.994';
  my $dest_dir_name = "$RootDirName/local/mecab-@{[mecab_version]}-@{[mecab_charset]}";
  return 0 unless install_tarball
      qq<http://mecab.googlecode.com/files/mecab-$mecab_version.tar.gz>
      => 'mecab' => $dest_dir_name,
      configure_args => [
        '--with-charset=' . $mecab_charset,
      ],
      check => sub { -x "@{[mecab_bin_dir_name]}/mecab-config" };
  return install_tarball
      'http://mecab.googlecode.com/files/mecab-ipadic-2.7.0-20070801.tar.gz'
      => 'mecab' => $dest_dir_name,
      configure_args => [
        #  --with-dicdir=DIR  set dicdir location
        '--with-charset=' . $mecab_charset,
        "--with-mecab-config=" . mecab_config_file_name,
      ],
      check => sub {
        return -f "@{[mecab_lib_dir_name]}/mecab/dic/ipadic/sys.dic";
      };
} # install_mecab

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
my $perl_version =
    defined $SpecifiedPerlVersion ? init_perl_version $SpecifiedPerlVersion :
    -f "$RootDirName/config/perl/version.txt" ? init_perl_version_by_file_name "$RootDirName/config/perl/version.txt" :
    init_perl_version undef;
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
    unless ($ENV{PMBP_NO_PERL_INSTALL}) {
      unshift @Command, {type => 'install-perl-if-necessary'};
    }
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
        {type => 'create-libs-txt-symlink'},
        {type => 'create-local-perl-latest-symlink'},
        {type => 'update-gitignore'};

    unless ($ENV{PMBP_NO_PERL_INSTALL}) {
      unshift @Command, {type => 'create-perlbrew-perl-latest-symlink'};
      unshift @Command, {type => 'install-perl-if-necessary'};
    }

  } elsif ($command->{type} eq 'print-pmbp-pl-etag') {
    my $etag = get_pmbp_pl_etag;
    print $etag if defined $etag;
  } elsif ($command->{type} eq 'update-pmbp-pl') {
    update_pmbp_pl;

  } elsif ($command->{type} eq 'update-gitignore') {
    update_gitignore;
  } elsif ($command->{type} eq 'add-to-gitignore') {
    add_to_gitignore [$command->{value}] => "$RootDirName/.gitignore";

  } elsif ($command->{type} eq 'print-latest-perl-version') {
    print get_latest_perl_version;
  } elsif ($command->{type} eq 'print-selected-perl-version') {
    print $perl_version;
  } elsif ($command->{type} eq 'print-perl-archname') {
    print get_perl_archname $PerlCommand, $perl_version;
  } elsif ($command->{type} eq 'install-perl') {
    info 0, "Installing Perl $perl_version...";
    install_perl $perl_version;
  } elsif ($command->{type} eq 'install-perl-if-necessary') {
    my $actual_perl_version = get_perl_version $PerlCommand || '?';
    unless ($actual_perl_version eq $perl_version) {
      info 0, "Installing Perl $perl_version...";
      install_perl $perl_version;
    }
  } elsif ($command->{type} eq 'create-perlbrew-perl-latest-symlink') {
    create_perlbrew_perl_latest_symlink $perl_version;

  } elsif ($command->{type} eq 'install-module') {
    delete_pmpp_arch_dir $PerlCommand, $perl_version if $pmpp_touched;
    info 0, "Installing @{[$command->{module}->as_short]}...";
    install_module $PerlCommand, $perl_version, $command->{module},
        module_index_file_name => $module_index_file_name;
  } elsif ($command->{type} eq 'install-modules-by-list') {
    delete_pmpp_arch_dir $PerlCommand, $perl_version if $pmpp_touched;
    my $module_index = PMBP::ModuleIndex->new_empty;
    if (defined $command->{file_name}) {
      read_pmb_install_list $command->{file_name} => $module_index;
    } else {
      read_install_list $RootDirName => $module_index, $perl_version,
          recursive => 1;
    }
    for ($module_index->to_list) {
      info 0, "Installing @{[$_->as_short]}...";
      install_module $PerlCommand, $perl_version, $_,
          module_index_file_name => $module_index_file_name;
    }
  } elsif ($command->{type} eq 'install-to-pmpp') {
    info 0, "Installing @{[$command->{module}->as_short]} to pmpp...";
    install_module $PerlCommand, $perl_version, $command->{module},
        module_index_file_name => $module_index_file_name, pmpp => 1;
    $pmpp_touched = 1;
  } elsif ($command->{type} eq 'install-by-pmpp') {
    info 0, "Copying pmpp modules...";
    copy_pmpp_modules $PerlCommand, $perl_version;
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
      install_module $PerlCommand, $perl_version, $_,
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
    open my $file, '>', $file_name or info_die "$0: $file_name: $!";
    info_writing 0, "lib paths", $file_name;
    print $file join ':', (get_lib_dir_names ($PerlCommand, $perl_version));
  } elsif ($command->{type} eq 'create-libs-txt-symlink') {
    my $real_name = get_libs_txt_file_name ($perl_version);
    my $link_name = "$RootDirName/config/perl/libs.txt";
    info_writing 3, 'libs.txt symlink', $link_name;
    mkdir_for_file $link_name;
    (unlink $link_name or info_die "$0: $link_name: $!")
        if -f $link_name || -l $link_name;
    (symlink $real_name => $link_name) or info_die "$0: $link_name: $!";
  } elsif ($command->{type} eq 'create-local-perl-latest-symlink') {
    my $real_name = "$RootDirName/local/perl-$perl_version";
    my $link_name = "$RootDirName/local/perl-latest";
    info_writing 3, 'perl-latest symlink', $link_name;
    make_path $real_name;
    remove_tree $link_name;
    symlink $real_name => $link_name or info_die "$0: $link_name: $!";
  } elsif ($command->{type} eq 'create-perl-command-shortcut') {
    create_perl_command_shortcut $perl_version, $command->{command};
  } elsif ($command->{type} eq 'write-makefile-pl') {
    mkdir_for_file $command->{file_name};
    open my $file, '>', $command->{file_name}
        or info_die "$0: $command->{file_name}: $!";
    info_writing 0, "dummy Makefile.PL", $command->{file_name};
    print $file q{
      use inc::Module::Install;
      name "Dummy";
      open my $file, "<", "config/perl/pmb-install.txt"
          or info_die "$0: config/perl/pmb-install.txt: $!";
      while (<$file>) {
        if (/^([0-9A-Za-z_:]+)/) {
          requires $1;
        }
      }
      Meta->write;
      Meta->write_mymeta_json;
    };
  } elsif ($command->{type} eq 'print-libs') {
    print join ':', (get_lib_dir_names ($PerlCommand, $perl_version));
  } elsif ($command->{type} eq 'set-module-index') {
    $module_index_file_name = $command->{file_name}; # or undef
    PMBP::Module->set_module_index_file_name ($command->{file_name});
  } elsif ($command->{type} eq 'prepend-mirror') {
    if ($command =~ m{^[^/]}) {
      $command->{url} = abs_path $command->{url};
    }
    unshift @CPANMirror, $command->{url};
  } elsif ($command->{type} eq 'print-pmtar-dir-name') {
    print pmtar_dir_name;
  } elsif ($command->{type} eq 'print-pmpp-dir-name') {
    print pmpp_dir_name;
  } elsif ($command->{type} eq 'init-pmtar-git') {
    init_pmtar_git;
    pmtar_git_pull;
  } elsif ($command->{type} eq 'init-pmpp-git') {
    init_pmpp_git;
    pmpp_git_pull;
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
    my $ver = get_module_version
        $PerlCommand, $perl_version, $command->{module};
    print $ver if defined $ver;
  } elsif ($command->{type} eq 'print-perl-path') {
    print get_perl_path ($perl_version);
  } elsif ($command->{type} eq 'print') {
    print $command->{string};

  } elsif ($command->{type} eq 'install-apache') {
    install_apache_httpd $command->{value};
  } elsif ($command->{type} eq 'install-mecab') {
    install_mecab;

  } else {
    info_die "Command |$command->{type}| is not defined";
  }
} # while @Command

delete_pmpp_arch_dir $PerlCommand, $perl_version if $pmpp_touched;
destroy;
info 0, "Done: " . (time - $start_time) . " s";
info_end;
delete_info_file unless $PreserveInfoFile;

## ------ End of main ------

package PMBP::Module;
use Carp;

my $ModulePackagePathnameMapping;
my $LoadedModuleIndexFileName;

sub set_module_index_file_name ($$) {
  my (undef, $file_name) = @_;
  return unless defined $file_name;
  return if $LoadedModuleIndexFileName->{$file_name};
  main::_read_module_index $file_name => sub {
    $ModulePackagePathnameMapping->{$_[0]->[0]} = $_[0]->[2];
  };
  $LoadedModuleIndexFileName->{$file_name} = 1;
} # set_module_index_file_name

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
    if ($self->{url} =~ m{/authors/id/(.+\.(?:tar\.(?:gz|bz2)|zip|tgz))$}) {
      $self->{pathname} = $1;
    } elsif ($self->{url} =~ m{([^/]+\.(?:tar\.(?:gz|bz2)|zip|tgz))$}) {
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
    main::get_default_mirror_file_name unless $ModulePackagePathnameMapping;
    my $pathname = $ModulePackagePathnameMapping->{$_[0]->{package}};
    if (defined $pathname) {
      return $_[0]->{pathname} = $pathname;
    }

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
    $pathname =~ s{\.(?:tar\.(?:gz|bz2)|zip|tgz)$}{};
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

=head1 SYNOPSIS

  $ perl bin/pmbp.pl --update
  $ perl bin/pmbp.pl --install

  $ perl bin/pmbp.pl OPTIONS... COMMANDS...
  $ perl bin/pmbp.pl --help
  $ perl bin/pmbp.pl --version

=head1 DESCRIPTION

The C<pmbp.pl> script is a tool to manage dependency for Perl
applications.  It can be possible to automate installation process of
required version of Perl and required Perl modules, in the C<local/>
directory under the application's directory (i.e. without breaking
your system and home directory).

=head1 OPTIONS

There are two kinds of options for the script: normal options and
commands.  Normal options specify how the script behave.  Normal
options can be specified at most once respectively and their order is
not significant.  Commands describe the action of the script.
Commands can be specified multiple times and their order are
significant.  The number and order of commands indicate the number and
order of actions.  Commands and other options can be mixed.

=head2 Normal options

=head2 Options on target directories

=over 4

=item --root-dir-name="path/to/dir"

Specify the root directory of the application.  Various operations by
the script is performed relative to this directory.  The value must be
a valid path to the directory in the platform.  Unless specified, the
current directory is used as the root directory.  If there is no such
a directory, it is first created by the script.  Anyway, the directory
must be writable by the user executing the script.

=item --pmtar-dir-name="path/to/dir"

Specify the directory for tarball packages of Perl modules.  Unless
specified, the C<deps/pmtar> directory in the root directory is
assumed.  The path is interpreted as relative to the B<application
root directory> name rather than the current directory.  Any tarball
packages used to install Perl modules is saved under this directory.
This option can also be specified as C<PMBP_PMTAR_DIR_NAME>
environment variable.

=item --pmpp-dir-name="path/to/dir"

Specify the directory for pure-Perl modules.  Unless specified, the
C<deps/pmpp> directory in the root directory is assumed.  The path is
interpreted as relative to the B<application root directory> name
rather than the current directory.  Pure-Perl modules prepared during
the C<--update> command is placed under this directory for saving time
to build those modules in the C<--install> command.  This option can
also be specified as C<PMBP_PMPP_DIR_NAME> environment variable.

=back

=head2 Options for downloading

=over 4

=item --download-retry-count="integer"

Specify the number of retries of download.  Each download performed by
the script itself (not including downloads by cpanm or perlbrew) is
tried at most I<n> + 1 times, where I<n> is the number specified by
this option.  Defaulted to 3.

=back

=head2 Options for Perl interpreter

=over 4

=item --perl-command="perl"

Specify the path to the C<perl> command used by the script.  If this
option is not specified, the C<perl> command in the default search
path (determined by the C<PATH> environment variable and the
C<--perl-version> option) is used.

=item --perl-version="5.n.m"

Specify the Perl version to be used for processing of the script.  If
the C<--install-perl> command is invoked, then the value must be one
of Perl versions.  Otherwise, it must match the version of the default
C<perl> command.

If this option is not specified, the value of the environment variable
C<PMBP_PERL_VERSION>, if specified, is used.

Otherwise, if there is C<config/perl/version.txt> in the root
directory, then the content of the file is used as the version
instead.  The content of the file must be a valid value for the
C<--perl-version> option, optionally followed by a newline.

Otherwise, if this option is not specified and there is no
C<config/perl/version.txt>, the version of the default C<perl> command
is used.  The default C<perl> command is determined by the
C<--perl-command> option.

Perl version string C<latest> represents the latest stable version of
Perl.

=item --perlbrew-installer-url="URL"

Specify the URL of the perlbrew installer.  The default URL is
C<http://install.perlbrew.pl/>.

=item --perlbrew-parallel-count="integer"

Specify the number of parallel processes of perlbrew (used for the
C<-j> option to the C<perlbrew>'s C<install> command).  The default
value is the value of the environment variable C<PMBP_PARALLEL_COUNT>,
or C<1>.

=back

=head2 Options for Perl modules

=over 4

=item --cpanm-url="URL"

Specify the URL of the cpanm source code.  Unless specified,
C<http://cpanmin.us/> is used.

=back

=head2 Options on system commands

Please note that "command" in this subsection means some executable in
your system and is irrelevant to the "command" kind of options to the
script.

=over 4

=item --wget-command="wget"

Specify the path to the C<wget> command used to download files from
the Internet.  If this option is not specified, the C<wget> command in
the current C<PATH> is used.

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

=item --brew-command="path/to/brew"

Specify the path to the C<brew> command (homebrew).  If this option is
not specified, the C<brew> command in the default search path is used.

=item --mecab-charset="utf-8/euc-jp/sjis"

Specify the charset of MeCab.  If this option is not specified,
C<utf-8> is used as charset.

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

If the option is specified or at least one of C<PMBP_DUMP_BEFORE_DIE>
and C<TRAVIS> environment variables is set to a true value, the
content of the "info file" is printed to the standard error output
before the script aborts due to some error.  This option is
particularly useful if you don't have access to the info file but you
does have access to the output of the script (e.g. in some CI
environment).

=back

=head2 Help options

There are two options to show descriptions of the script.  If one of
these options are specified, any other options are ignored.  The
script exits after the descriptions are printed.

=over 4

=item --help

Show usage of various options supported by the script.

=item --version

Show name, author, and license of the script.

=back

=head2 Higher-level commands

There are two commands which are expected to cover most of use cases
of the script.  Most of functionality these commands provide are
combination of other commands such that if you want more sensitive
control for what the script should do, maybe you'd like to invoke
commands described in following subsections.  These two commands and
those commands can be combined, if desired.

=over 4

=item --install

The C<--install> command setup required environment for the
application, including Perl and Perl modules.

If the application, specified by the C<--root-dir-name> option,
contains the C<config/perl/pmb-install.txt>, required Perl modules
listed in the file are installed into the C<local/perl-{version}/pm>
directory.  Otherwise, required modules are scanned from various
sources, including C<carton.lock>, C<Makefile.PL>, C<cpanfile>, Perl
modules, and Perl scripts within the directory and then installed.

If the application specifies the version of the Perl by
C<config/perl/version.txt>, that version of Perl is installed int o
C<local/perlbrew/perls/perl-{version}> before installation of any
module.

The command generates C<config/perl/libs.txt>, which contains the
paths to application's Perl modules (see C<--write-libs-txt> for
details on its content).

You might also want to invoke C<--create-perl-command-shortcut>
command after the C<--install> for convinience of execution of your
application.

The C<--install> command can be invoked whenever you want, to reflect
latest state of your application.  Only differences from previous
invocation are processed by the command.  If you'd like to clean up
your environment, delete the C<local/> directory and run the command
again.

=item --update

The C<--update> command generates the list of required components,
which is portable such that you might want to add them to the
application repository (e.g. Git repository) for later usage by
C<--install>.

The command generates C<config/perl/pmb-install.txt>, which contains
full list of required Perl modules.  The file is generated from
various kinds of dependency descriptions, including C<Makfile.PL> and
C<carton.lock> of the application itself and some submodules.  It is
encouraged to list the direct dependnecy of the application in the
"pmb install list" format; it is simply the newline-separated list of
Perl module names, saved as C<config/perl/modules.txt>, though this is
not required.

The command collects tarballs for required modules and save them into
the C<deps/pmtar> directory.  If your application is a Git repository,
you might want to handle this directory as a submodule.  (See also
C<--pmtar-dir-name> option.)

In addition, the commands creates a copy of set of required pure Perl
modules at C<deps/pmpp> directory.  You might also want to handle this
directory as Git submodule.

These files would simplify processing and eliminate network accesses
by the C<--install> command.

The C<--update> command can be invoked whenever you want, to update
list of dependency and to update CPAN modules.  Only differences from
previous invocation are used to update various files.  If you'd like
to clean up such files, delete C<deps>,
C<config/perl/pmb-install.txt>, (and C<local/> if desired), and then
invoke C<--update> again.

=back

=head2 Commands for pmbp.pl

=over 4

=item --update-pmbp-pl

Download the latest version of the pmbp.pl script, if available, to
C<local/bin/pmbp.pl> in the root directory.

=item --print-pmbp-pl-etag

Print the HTTP C<ETag> value of the current pmbp.pl script, if
available.  This is internally used to detect newer version of the
script by the C<--update-pmbp-pl> command.  If the pmbp.pl script is
not retrieved by the C<--update-pmbp-pl> command, the script does not
know its C<ETag> and this command would print nothing.

=back

=head2 Commands for Perl interpreter

=over 4

=item --print-latest-perl-version

Print the version number of the latest stable release of Perl to the
standard output.  At the time of writing, this command prints the
string C<5.16.1>.

=item --print-selected-perl-version

Print the selected Perl version.  For example, if C<--perl-version>
command is not specified, the current Perl's version is printed like
C<5.10.1>.  Another example is that if the
C<--perl-version-by-file-name> points the file containing the string
C<latest>, the command might print the string C<5.16.1>.

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

=item --print-perl-archname

Print the C<$Config{archname}> value of the C<perl> command to be used
for installation and other commands.  For example, C<x86_64-linux> on
some Linux system.  Please note that this command fails if the
specified version of Perl is not yet installed.  Therefore this
command should be invoked I<after> C<--install-perl> (or C<--install>)
command.  Please also note that if the command is invoked before the
Perl with the same version as the current Perl (which is running the
pmbp.pl script) is compiled by C<--install-perl> command, and if their
archnames are different, the archname printed by the command would be
different from what you expect.

=item --create-perl-command-shortcut="command-name"

Create a shell script to invoke a command with environement variables
C<PATH> and C<PERL5LIB> set to appropriate values for any locally
installed Perl and its modules under the "root" directory.

The command name can be prefixed by path
(e.g. C<hoge/fuga/command-name>).  If path is specified, the shell
script is created within that directory instead (i.e. in C<hoge/fuga>
in the example).

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

=back

=head2 Commands for Perl modules

=over 4

=item --install-module="Module::Name"

Install the Perl module, whose package name is specified as the
argument to the command.  The module is installed into the
C<local/perl-VERSION/pm> directory within the root directory, where
C<VERSION> is current Perl version (see C<--perl-version> option).

If the module is specified in I<Module::Name> format, the package name
is looked up from CPAN package index.  If the module is specified in
I<Module::Name~version> format, the package name with version greater
than or equal to the specified value is looked up.  If the module is
specified in I<Module::Name=URL> format, the tarball package located
at the URL is downloaded and then installed, with the specified name
of the module.

If the specified module is not found, or the installation has failed,
the script exits unsuccessfully.  If any missing dependency has been
found during the installation process, the script performs its best
effort to install the dependency and then retries several times.  If
the detected dependency is non-Perl software components, its behavior
depends on whether the C<--execute-system-package-installer> option is
specified or not.

=item --install-modules-by-file-name="path/to/list.txt"

Install zero or more Perl modules listed in the specified text file.
The argument to the command must be a path to the list file, relative
to the current directory.  If the file is not found the script simply
ignores the command (but reporting the failure) and does not fail.

The file must be in the "pmb install list" format, that is,
newline-character separated list of zero or more Perl module
specifications.  Each line must identify the Perl module in the format
that is allowed as the argument to the C<--install-module> command.
Empty lines and lines starting with the C<#> character are ignored.

=item --install-modules-by-list

Install zero or more Perl modules listed in the text files.  Following
files under the root directory are examined:

  config/perl/modules.txt
  config/perl/modules.*.txt
  modules/*/config/perl/modules.txt
  modules/*/config/perl/modules.*.txt

Each file must be in the "pmb install list" format, as described for
the C<--install-modules-by-file-name> command.

=item --install-to-pmpp="Module::Name"

Install the Perl module into the "pmpp" directory (see
C<--pmpp-dir-name> option), instead of the "pm" directory.  Except for
the installed directory, this command has same effect as the
C<--install-module> command.

=item --update-pmpp-by-file-name="path/to/list.txt"

Install zero or more Perl modules listed in the specified text file,
into the "pmpp" directory (see C<--pmpp-dir-name> option), instead of
the "pm" directory.  Except for the installed directory, this command
has same effect as the C<--install-modules-by-file-name> command.

=item --update-pmpp-by-list

Install zero or more Perl modules, listed in text files, into the
"pmpp" directory (see C<--pmpp-dir-name> option), instead of the "pm"
directory.  Except for the installed directory, this command has same
effect as the C<--install-modules-by-list> command.

=item --install-by-pmpp

Copy pure-Perl modules prepared in the "pmpp" directory (see
C<--pmpp-dir-name> option) to the "pm" directory (i.e. the directory
to which Perl modules are installed by the C<--install-module>
command).

=item --scandeps="Module::Name"

Scanning dependency of the specified Perl module.  The scanned result
is saved in the C<deps> directory in the "pmtar" directory (see
C<--pmtar-dir-name> option).  If there is already scanned result in
the directory, this command does nothing.  The argument to the command
must be in the same format as the argument to the C<--install-module>
command.

=item --select-module="Module::Name"

Same as the C<--scandeps> command, but add the specified module and
its dependency in to the "list of the selected module" of the script.

=item --select-modules-by-file-name="path/to/list.txt"

Similar to the C<--select-module> command, but the list of zero or
more Perl modules to be selected are obtained from the specified file.
The file must be in the "pmb install list" format (see
C<--install-modules-by-file-name>).

=item --select-modules-by-list

Similar to the C<--select-modules-by-file-name> command, but the list
files are chosen in the same rule as the C<--install-modules-by-list>
command.

=item --print-scanned-dependency="path/to/modules.txt"

Scan Perl modules and scripts in the root directory and generate list
of required Perl modules in the "pmb install list" format, writing
into the specified file.  This command should be useful for generating
initial content of the C<config/perl/modules.txt>.

=item --read-module-index="path/to/packages.txt"

Read the index of Perl modules, in the CPAN package list format.  The
index is used for finding modules in install and scandeps commands.
See also C<--set-module-index> command.

=item --read-carton-lock="path/to/carton.lock"

Read the index of Perl modules, in the "carton.lock" format generated
by L<Carton>.

=item --write-module-index="path/to/packages.txt"

Write the index of known Perl modules, holded by the script, into the
specified file.

=item --write-pmb-install-list="path/to/modules.txt"

Write the "list of the selected modules" into the specified file, in
the "pmb install list" format.

=item --write-install-module-index="path/to/packages.txt"

Write the "list of the specified modules" into the specified file, in
the CPAN package list format.

=item --write-libs-txt="path/to/libs.txt"

Write the list of directories for Perl modules of the application, as
C<:> separated list of full paths.  The list contains:

  {root-dir-name}/lib
  {root-dir-name}/modules/*/lib
  {root-dir-name}/local/submodules/*/lib
  {root-dir-name}/local/perl-{version}/pm/lib/perl5/{archname}
  {root-dir-name}/local/perl-{version}/pm/lib/perl5

... at the time of execution.  This file can be used as value of the
C<PERL5LIB> environment variable, like:

  $ PERL5LIB="`cat path/to/libs.txt`" perl myapp.pl

=item --print-libs

Print the list of directories for Perl modules of the application, as
C<:> separated list of full paths.  This is same as the content of the
file generated by the C<--write-libs-txt> command.

=item --write-makefile-pl="path/to/Makefile.PL"

Write the C<Makefile.PL> that describes the dependency of the
application using the C<config/perl/pmb-install.txt>.  The file can be
created by the C<--update> command (or the
C<--write-pmb-install-list=config/perl/pmb-install.txt> after
selecting relevant modules).  This command might or might not be
useful for integration with C<Makefile.PL> based application
dependency management solutions.

=item --print-module-pathname="Perl::Module::Name"

Print the "pathname" of the specified module, if found in the CPAN
package index.  The "pathname" of the module is the string like:
C<A/AU/AUTHOR/Perl-Module-Name-1.23.tar.gz>.

=item --print-module-version="Perl::Module::Name"

Print the version of the specified module, if installed.  If the
specified module is not installed, nothing is printed.

The version of the module is extracted from the module by C<use>ing
the module and then accessing to the C<$VERSION> variable in the
package of the module.

=item --print-perl-core-version="Perl::Module::Name"

Print the first version of Perl where the specified module is bundled
as a core module, as returned by L<Module::CoreList>.  For example,
C<5.007003> is printed if the module specified is C<Encode>.  The
L<Module::CoreList> module is automatically installed for the script
if not available.  If the specified module is not part of core Perl
distribution, nothing is printed.

=item --print-pmtar-dir-name

Print the effective "pmtar" directory as full path name.  If the
"pmtar" directory is not exist, this command creates one.  See also
C<--pmtar-dir-name> option.

=item --print-pmpp-dir-name

Print the effective "pmpp" directory as full path name.  If the "pmpp"
directory is not exist, this command creates one.  See also
C<--pmpp-dir-name> option.

=back

=head2 Commands for controling cpanm behavior

=over 4

=item --set-module-index="path/to/index.txt"

Set the path to the CPAN package index, relative to the current
directory, used as input to the C<cpanm> command.

=item --prepend-mirror=URL

Prepend the specified CPAN mirror URL to the list of mirrors.

=back

=head2 Other commands

=over 4

=item --print="string"

Print the string.  Any string can be specified as the argument.  This
command might be useful to combine multiple C<--print-*> commands.

=item --install-apache="VERSION"

Install Apache HTTP server into C<local/apache/httpd-VERSION>.  The
value identifies major and minor versions of the Apache to install,
which must be one of: C<1.3>, C<2.0>, C<2.2>, or C<2.4>.

Note that this command is automatically invoked when you are
instructed to install mod_perl.

If the specified version of Apache is already installed, this command
does nothing.

=item --install-mecab

Install MeCab into C<local/mecab-VERSION-CHARSET>.  If MeCab is
already installed, this command does nothing.

=item --add-to-gitignore="path"

Add the specified file name or path to the C<.gitignore> file in the
root directory (if not yet).

=back

=head1 ENVIRONMENT VARIABLES

=over 4

=item http_proxy

Specify the proxy host.  See documentation for the C<wget> command for
more information.

=item PMBP_DUMP_BEFORE_DIE

Set the default for the C<--dump-info-file-before-die> option.

=item PMBP_PARALLEL_COUNT

Set the default value for the C<--perlbrew-parallel-count> option.
Defaulted to C<4> if the environment variable C<TRAVIS> is set.

=item PMBP_PERL_VERSION

Set the default value for the C<--perl-version> option.

=item PMBP_PMTAR_DIR_NAME, PMBP_PMPP_DIR_NAME

Set the default value for the C<--pmtar-dir-name> and
C<--pmpp-dir-name> options, respectively.  See their description for
details.

=item PMBP_FALLBACK_PMTAR_DIR_NAME

If the directory specified by C<--pmtar-dir-name> option or
C<PMBP_PMTAR_DIR_NAME>, or their default value, i.e. C<deps/pmtar>,
does not exist, but if there is the directory specified by the
C<PMBP_FALLBACK_PMTAR_DIR_NAME> environment variable, then the
directory is used instead.

=item PMBP_VERBOSE

Set the default verbosity level.  See C<--verbose> option for details.

=item TRAVIS

The C<TRAVIS> environment variable affects log level.  Additionally,
the C<TRAVIS> environment variable enables automatical installation of
Debian apt packages, if required.  See description for related options
for more information.

=back

=head1 FILES

=head2 .gitignore

The C<--install> command edits C<.gitignore> file in the root
directory to let Git ignore locally-installed files such as the
C<local/> directory.

=head2 config/perl/modules.txt, config/perl/modules.*.txt

The list of required Perl modules, in the "pmb install list" format.
You can described the list of Perl modules required by the application
in these files such that commands including C<--install> and
C<--install-perl-modules-by-list> can find required modules without
sniffing your Perl modules or executing any script that could have any
side-effect.  See C<--install-perl-modules-by-file-name> for details.

These files can also be provided for submodules.

=head2 config/perl/pmb-install.txt

The list of required Perl modules, directly or indirectly, by the
application, generated by the C<--update> command.  This file would be
used by the C<--install> command to omit the dependency scanning
process.  Although this file is redundant with various sources of
dependencies, it is expected to be part of the application repository
(i.e. added to the Git repository of the application).

=head2 config/perl/libs.txt

The C<--install> command generates (or overwrites) the file
C<config/perl/libs.txt>, which contains C<:>-separated list of paths
to C<lib>, C<modules/*/lib>, and locally-installed Perl modules.  This
file is intended to be used as value of the C<PERL5LIB> environment
variable, like:

  PERL5LIB="`cat config/perl/libs.txt`" perl ...

In fact this file is a symlink to
C<local/config/perl/libs-$perl_version-$Config{archname}.txt>.  This
file is placed under the C<config/perl> directory for backward
compatibility.  You might want to add the file name to the
C<.gitignore> file.

=head2 config/perl/version.txt

Specify the version of Perl to be installed by C<--install-perl>.  See
description for C<--perl-version> for more information.

=head2 local/bin/pmbp.pl

It is recommended that the pmbp.pl script should be placed in the
C<local/bin> directory under the root directory.  Additionally, before
the installation process, you should run the following command to keep
the script up-to-date:

  $ perl local/bin/pmbp.pl --update-pmbp-pl

=head2 local/perl-latest

The C<--install> command generates (or overwrites) the C<perl-latest>
symlink, which points to the C<local/perl-{perl-version}> directory.
In other word, C<local/perl-latest/> contains files of the last
C<--install>ation of Perl modules.  Originally the directory was
intended to contain files for "latest" version of Perl, which is why
the symlink is named C<perl-latest>.  Use of this symlink is
deprecated.

=head2 local/perlbrew/perls/perl-latest

The C<--install> command generates (or overwrites) the C<perl-latest>
alias to the Perl with the currently selected version for the local
perlbrew (i.e. C<local/perlbrew/perls/perl-latest/bin/perl> becomes
the current version of Perl).  Please note that the "perl-latest" does
not necessariliy the latest version of Perl.  Use of this alias is
depreacated.

=head1 SEE ALSO

See also tutorial and additional descriptions located at
<https://github.com/wakaba/perl-setupenv/blob/master/doc/pmbp-tutorial.pod>.

See the tutorial for how to install mod_perl.

=head1 AUTHOR

Wakaba <wakaba@suikawiki.org>.

=head1 LICENSE

Copyright 2012 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
