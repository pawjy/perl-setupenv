=head1 NAME

pmbp.pl - Perl application environment manager

=cut

use strict;
use warnings;
use warnings FATAL => 'recursion';
use Config;
use Cwd;
use File::Spec ();
use Getopt::Long;

## Some environment does not have this module.
my $TimeHiResError;
BEGIN { eval q{ use Time::HiRes qw(time); 1 } or $TimeHiResError = $@ };

my $PlatformIsWindows = $^O eq 'MSWin32';
my $PlatformIsMacOSX = $^O eq 'darwin';
my $PerlCommand = 'perl';
my $SpecifiedPerlVersion = $ENV{PMBP_PERL_VERSION};
my $PerlOptions = {};
$PerlOptions->{relocatable} = 1 if $ENV{PMBP_HEROKU_BUILDPACK};
my $WgetCommand = 'wget';
my @WgetOption = ($ENV{PMBP_IGNORE_TLS_ERRORS} ? '--no-check-certificate' : ());
my $CurlCommand = 'curl';
my @CurlOption = ($ENV{PMBP_IGNORE_TLS_ERRORS} ? '--insecure' : ());
my $GitCommand = 'git';
my $SudoCommand = 'sudo';
my $AptGetCommand = 'apt-get';
my $YumCommand = 'yum';
my $BrewCommand = 'brew';
my $WhichCommand = $PlatformIsWindows ? 'where' : 'which';
my $DownloadRetryCount = 2;
my $PerlbrewInstallerURL = q<https://raw.githubusercontent.com/gugod/App-perlbrew/develop/perlbrew-install>; # q<http://install.perlbrew.pl/>;
my $PerlbrewParallelCount = $ENV{PMBP_PARALLEL_COUNT} || ($ENV{CI} ? 4 : 1);
my $SavePerlbrewLog = not $ENV{CI};
my $CPANMURL = q<https://raw.githubusercontent.com/miyagawa/cpanminus/master/cpanm>; # q<http://cpanmin.us/>;
my $MakefileURL = q<https://raw.githubusercontent.com/wakaba/perl-setupenv/master/Makefile.pmbp.example>;
my $ImageMagickURL = q<https://www.imagemagick.org/download/ImageMagick.tar.gz>;
my $RootDirName = '.';
my $FallbackPMTarDirName = $ENV{PMBP_FALLBACK_PMTAR_DIR_NAME};
my $PMTarDirName = $ENV{PMBP_PMTAR_DIR_NAME};
my $PMPPDirName = $ENV{PMBP_PMPP_DIR_NAME};
my @Command;
my @CPANMirror;
my $Verbose = $ENV{PMBP_VERBOSE} || 0;
my $PreserveInfoFile = 0;
my $DumpInfoFileBeforeDie = $ENV{PMBP_DUMP_BEFORE_DIE} || $ENV{CI} || 0;
my $ExecuteSystemPackageInstaller = $ENV{CI} || 0;
my $MeCabCharset;
my $HelpLevel;

my @Argument = @ARGV;

GetOptions (
  '--perl-command=s' => \$PerlCommand,
  '--curl-command=s' => \$CurlCommand,
  '--wget-command=s' => \$WgetCommand,
  '--git-command=s' => \$GitCommand,
  '--sudo-command=s' => \$SudoCommand,
  '--apt-get-command=s' => \$AptGetCommand,
  '--yum-command=s' => \$YumCommand,
  '--brew-command=s' => \$BrewCommand,
  '--download-retry-count=s' => \$DownloadRetryCount,
  '--perlbrew-installer-url=s' => \$PerlbrewInstallerURL,
  '--perlbrew-parallel-count=s' => \$PerlbrewParallelCount,
  '--cpanm-url=s' => \$CPANMURL,
  '--root-dir-name=s' => \$RootDirName,
  '--pmtar-dir-name=s' => \$PMTarDirName,
  '--pmpp-dir-name=s' => \$PMPPDirName,
  '--perl-version=s' => \$SpecifiedPerlVersion,
  '--perl-relocatable' => sub { $PerlOptions->{relocatable} = 1 },
  '--verbose' => sub { $Verbose++ },
  '--preserve-info-file' => \$PreserveInfoFile,
  '--dump-info-file-before-die' => \$DumpInfoFileBeforeDie,
  '--execute-system-package-installer' => \$ExecuteSystemPackageInstaller,
  '--mecab-charset' => \$MeCabCharset,

  '--help' => sub { $HelpLevel = {-exitstatus => 0, -verbose => 1} },
  '--version' => sub { $HelpLevel = {-exitstatus => 0, -verbose => 99, -sections => [qw(NAME AUTHOR LICENSE)]} },

  '--install-module=s' => sub {
    my $module = PMBP::Module->new_from_module_arg ($_[1]);
    push @Command, {type => 'install-module', module => $module};
  },
  '--install-modules-by-file-name=s' => sub {
    push @Command, {type => 'install-modules-by-list', file_name => $_[1]};
  },
  '--install-modules-by-dir-name=s' => sub {
    push @Command, {type => 'install-modules-by-list', dir_name => $_[1]};
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
  '--add-git-submodule=s' => sub {
    my ($parent, $url) = split /\s+/, $_[1], 2;
    if (defined $url) {
      push @Command, {type => 'add-git-submodule',
                      parent_dir_name => $parent, url => $url};
    } else {
      push @Command, {type => 'add-git-submodule', url => $parent};
    }
  },
  '--add-git-submodule-recursively=s' => sub {
    my ($parent, $url) = split /\s+/, $_[1], 2;
    if (defined $url) {
      push @Command, {type => 'add-git-submodule',
                      parent_dir_name => $parent, url => $url,
                      recursive => 1};
    } else {
      push @Command, {type => 'add-git-submodule', url => $parent,
                      recursive => 1};
    }
  },
  '--create-perl-command-shortcut=s' => sub {
    ## See also: |create_perl_command_shortcut_by_file|
    my %args;
    if ($_[1] =~ s/^\@//) {
      $args{relocatable} = 1;
    }
    if ($_[1] =~ /=/) {
      # ../myapp=bin/myapp.pl
      my ($file_name, $command) = split /=/, $_[1], 2;
      if ($command =~ s/^(\S+)\s+(?=\S)//) {
        # ../myapp=perl bin/myapp.pl
        $command = [$1, $command];
      }
      push @Command,
          {type => 'write-libs-txt'},
          {type => 'write-relative-libs-txt'},
          {type => 'create-perl-command-shortcut',
           file_name => $file_name,
           command => $command, args => \%args};
    } elsif ($_[1] =~ m{/([^/]+)$}) {
      # local/bin/hoge (== local/bin/hoge=hoge)
      push @Command,
          {type => 'write-libs-txt'},
          {type => 'write-relative-libs-txt'},
          {type => 'create-perl-command-shortcut',
           file_name => $_[1],
           command => $1, args => \%args};
    } else {
      # perldoc (== perldoc=perldoc)
      push @Command,
          {type => 'write-libs-txt'},
          {type => 'write-relative-libs-txt'},
          {type => 'create-perl-command-shortcut',
           file_name => $_[1],
           command => $_[1], args => \%args};
    }
  },
  '--create-exec-command=s' => sub {
    my %args;
    if ($_[1] =~ s/^\@//) {
      $args{relocatable} = 1;
    }
    push @Command,
        {type => 'write-libs-txt'},
        {type => 'write-relative-libs-txt'},
        {type => 'create-perl-command-shortcut', file_name => $_[1],
         args => \%args};
  },
  '--print-scanned-dependency=s' => sub {
    push @Command, {type => 'print-scanned-dependency',
                    dir_name => $_[1]};
  },
  '--print=s' => sub {
    push @Command, {type => 'print', string => $_[1]};
  },
  '--install-perl-app=s' => sub {
    if ($_[1] =~ s/^([0-9A-Za-z_-]+)=//) {
      push @Command, {type => 'install-perl-app', name => $1, url => $_[1]};
    } else {
      push @Command, {type => 'install-perl-app', url => $_[1]};
    }
  },
  '--update-pmbp-pl' => sub {
    push @Command, {type => 'update-pmbp-pl', branch => 'master'};
  },
  '--update-pmbp-pl-staging' => sub {
    push @Command, {type => 'update-pmbp-pl', branch => 'staging'};
  },
  '--create-bootstrap-script=s' => sub {
    my @f = split /\s+/, $_[1], 2;
    die "Bad --create-bootstrap-script argument"
        unless defined $f[1] and length $f[1];
    push @Command, {type => 'create-bootstrap-script',
                    template_file_name => $f[0],
                    result_file_name => $f[1]};
  },
  (map {
    my $n = $_;
    ("--$n=s" => sub {
      push @Command, {type => $n, value => $_[1]};
    });
  } qw(install-apache create-pmbp-makefile)),
  (map {
    my $n = $_;
    ("--$n=s" => sub {
      push @Command, {type => $n, file_name => $_[1]};
    });
  } qw(write-dep-graph read-pmbp-exclusions-txt)),
  '--write-dep-graph-springy=s' => sub {
    push @Command, {type => 'write-dep-graph',
                    file_name => $_[1], format => 'springy'};
  },
  (map {
    my $n = $_;
    ("--$n=s" => sub {
      my $module = PMBP::Module->new_from_module_arg ($_[1]);
      push @Command, {type => $n, module => $module};
    });
  } qw(print-module-pathname print-module-version)),
  '--install-commands=s' => sub {
    push @Command, {type => 'install-commands',
                    value => [grep { length $_ } split /\s+/, $_[1]]};
  },
  (map {
    my $name = $_;
    ("--install-$name" => sub {
       push @Command, {type => 'install-commands', value => [$name]};
    });
  } qw(git curl wget make gcc mysqld mysql-client ssh-keygen)),
  (map {
    my $n = $_;
    ("--$n" => sub {
      push @Command, {type => $n};
    });
  } qw(
    update install
    print-pmbp-pl-etag print-cpan-top-url
    install-perl print-latest-perl-version print-selected-perl-version
    print-perl-archname print-libs
    print-pmtar-dir-name print-pmpp-dir-name print-perl-path
    print-submodule-components
    install-mecab install-svn install-awscli
    install-openssl install-openssl-if-mac install-openssl-if-old
    print-openssl-stable-branch print-openssl-version
    print-libressl-stable-branch
    init-git-repository
    help-tutorial
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
sub abs_path ($);
make_path ($RootDirName);
$RootDirName = abs_path ($RootDirName);

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
    require IO::File;
    open $InfoFile, '>', $InfoFileName or die "$0: $InfoFileName: $!";
    $InfoFile->autoflush (1);
    info_writing (0, "operation log file", $InfoFileName);
  } # open_info_file
  
  sub delete_info_file () {
    close $InfoFile;
    unlink $InfoFileName;
  } # delete_info_file

  my $InfoLineCount = 0;
  sub info ($$) {
    unless (defined $InfoFile) {
      print STDERR $_[1], ($_[1] =~ /\n\z/ ? "" : "\n");
      return;
    }

    if ($Verbose >= $_[0]) {
      $InfoNeedNewline--, print STDERR "\n" if $InfoNeedNewline;
      if ($_[1] =~ /\.\.\.\z/) {
        print STDERR $_[1];
        $InfoNeedNewline = 1;
      } else {
        print STDERR $_[1], ($_[1] =~ /\n\z/ ? "" : "\n");
      }
      $InfoLineCount = 0;
    } else {
      $InfoLineCount++;
      if ($InfoLineCount < 10) {
        print STDERR ".";
      } elsif ($InfoLineCount < 100 and $InfoLineCount % 10 == 0) {
        print STDERR ":";
      } elsif ($InfoLineCount < 1000 and $InfoLineCount % 100 == 0) {
        print STDERR "+";
      } elsif ($InfoLineCount % 1000 == 0) {
        print STDERR "*";
      }
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
    print $InfoFile Carp::longmess (), "\n";
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
      print STDERR "$0 failed\n";
    } else {
      print STDERR "$0 failed; See $InfoFileName for details\n";
    }

    my $dead_file_name = "$RootDirName/config/perl/pmbp-dead.txt";
    if (-f $dead_file_name) {
      if (open my $file, '<', $dead_file_name) {
        print STDERR "\n";
        while (<$file>) {
          s/\{InfoFileName\}/$InfoFileName/g;
          print STDERR $_;
        }
        print STDERR "\n";
      } else {
        warn "$dead_file_name: $!\n";
      }
    }

    exit 1;
  } # info_die

  sub info_writing ($$$) {
    info $_[0], join '', "Writing ", $_[1], " ", File::Spec->abs2rel ($_[2]), " ...";
  } # info_writing

  sub info_end () {
    $InfoNeedNewline--, print STDERR "\n" if $InfoNeedNewline;
  } # info_end

  sub info_closing () {
    if ($PreserveInfoFile) {
      info 0, "Operation log is saved as $InfoFileName";
    }
    delete_info_file unless $PreserveInfoFile;
  } # info_closing
}

{
  my %start_time;
  sub profiler_start ($) {
    $start_time{$_[0]} = time;
    info 6, sprintf "Profiler: %.3f: %s started",
        $start_time{$_[0]}, $_[0];
  } # profiler_start

  my %profile;
  sub profiler_stop ($) {
    my $time = time;
    $profile{$_[0]} += $time - $start_time{$_[0]};
    info 6, sprintf "Profiler: %.3f: %s stopped (%.3f s)",
        $time, $_[0], $time - $start_time{$_[0]};
  } # profiler_stop

  sub profiler_data () {
    return \%profile;
  } # profiler_data
}

sub copy_file ($$);
sub copy_log_file ($$);

sub get_real_time () {
  for my $url (
    q<https://ntp-a1.nict.go.jp/cgi-bin/jst>,
    q<https://time.akamai.com/?ms>,
  ) {
    my $ts_file_name = "$RootDirName/local/timestamp";
    _save_url ($url => $ts_file_name)
        or do { info 0, "Can't get current timestamp"; next };
    open my $file, '<', $ts_file_name or
        do { info 0, "Failed to open timestamp file"; next };
    local $/ = undef;
    my $timestamp = <$file>;
    if ($timestamp =~ m{\A([0-9.]+)\z}) { # Akamai format
      return 0+$1;
    } elsif ($timestamp =~ m{<BODY>\s*([0-9.]+)\s*</BODY>}s) { # NICT format
      return 0+$1;
    } else {
      info 0, "Timestamp file broken";
      copy_log_file $ts_file_name => 'timestamp';
    }
  }
  return undef;
} # get_real_time

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

sub update_pmbp_pl ($) {
  my $branch = shift;
  my $pmbp_pl_file_name = "$RootDirName/local/bin/pmbp.pl";
  my $etag;
  if (-f $pmbp_pl_file_name) {
    run_command 
        ([$PerlCommand, $pmbp_pl_file_name, '--print-pmbp-pl-etag'],
         discard_stderr => 1,
         onoutput => sub { $etag = $_[0]; 5 }) or undef $etag;
  }

  my $pmbp_url = qq<https://raw.githubusercontent.com/wakaba/perl-setupenv/$branch/bin/pmbp.pl>;
  my $temp_file_name = "$PMBPDirName/tmp/pmbp.pl.http";
  _save_url ($pmbp_url => $temp_file_name,
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

  info_writing 0, "latest version of pmbp.pl (branch $branch)", $pmbp_pl_file_name;
  mkdir_for_file ($pmbp_pl_file_name);
  copy_file $temp2_file_name => $pmbp_pl_file_name
      or info_die "$0: $pmbp_pl_file_name: $!";
} # update_pmbp_pl

sub save_pmbp_tutorial () {
  save_url (q<https://raw.github.com/wakaba/perl-setupenv/master/doc/pmbp-turorial.pod> => $RootDirName.'/local/pmbp/doc/pmbp-tutorial.pod',
      max_age => 3*24*60*60);
} # save_pmbp_tutorial


sub exec_show_pmbp_tutorial () {
  exec 'perldoc', $RootDirName.'/local/pmbp/doc/pmbp-tutorial.pod';
} # exec_show_pmbp_tutorial

sub create_bootstrap_script ($$) {
  my ($template_file_name, $result_file_name) = @_;
  local $/ = undef;

  info 0, "Loading script template |$template_file_name|...";
  profiler_start 'file';
  open my $file, '<', $template_file_name
      or info_die "$0: $template_file_name: $!";
  my $script = <$file>;
  profiler_stop 'file';

  my $bs_file_name = "$PMBPDirName/bin/bootstrap.sh";
  save_url
      (q<https://raw.githubusercontent.com/wakaba/perl-setupenv/master/bin/bootstrap.sh>
       => $bs_file_name,
       max_age => 24*60*60);

  profiler_start 'file';
  open my $bs_file, '<', $bs_file_name
      or info_die "$0: $bs_file_name: $!";
  my $bs = <$bs_file>;
  profiler_stop 'file';

  $script =~ s/\{\{INSTALL\}\}/$bs/g;

  info 0, "Generate |$result_file_name|...";
  profiler_start 'file';
  mkdir_for_file ($result_file_name);
  open my $result_file, '>', $result_file_name or
      info_die "$0: $result_file_name: $!";
  print $result_file $script;
  close $result_file;
  profiler_stop 'file';
} # create_bootstrap_script

## ------ Files and directories ------

sub abs_path ($) {
  my $x = eval { Cwd::abs_path ($_[0]) };
  if ($@) {
    info_die "|abs_path| |$_[0]| failed ($@)";
  }
  return $x;
} # abs_path

sub use_perl_core_module ($);

sub resolve_path ($$) {
  my $path = ($_[0] =~ m{^/}) ? $_[0] : "$_[1]/$_[0]";
  info_die "Base |$_[1]| is not an absolute path" unless $path =~ m{^/};
  $path .= '/';
  $path =~ s{//+}{/};
  $path =~ s{/\.(?=/)}{}g;
  while ($path =~ m{/\.\./}) {
    $path =~ s{/[^/]+/\.\.(?=/)}{}g;
    $path =~ s{^/\.\./}{/};
  }
  $path =~ s{/+$}{};
  return $path;
} # resolve_path

sub remove_tree ($) {
  if (eval { require File::Path }) {
    File::Path::rmtree ($_[0]);
  } else {
    (system 'rm', '-fr', $_[0]) == 0 or die $!;
  }
} # remove_tree

sub make_path ($) {
  if (eval { require File::Path }) {
    File::Path::mkpath ($_[0]);
  } else {
    if ($PlatformIsWindows) {
      system 'mkdir', $_[0];
      (system 'dir', $_[0]) == 0 or die $!;
    } else {
      (system 'mkdir', '-p', $_[0]) == 0 or die $!;
    }
  }
} # make_path

sub mkdir_for_file ($) {
  my $file_name = $_[0];
  $file_name =~ s{[^/\\]+$}{};
  make_path $file_name;
} # mkdir_for_file

sub copy_file ($$) {
  if (eval { require File::Copy }) {
    return File::Copy::copy ($_[0] => $_[1]);
  } else {
    return ((system 'cp', $_[0] => $_[1]) == 0); # with $!
  }
} # copy_file

sub copy_log_file ($$) {
  my ($file_name, $module_name) = @_;
  my $log_file_name = $module_name;
  $log_file_name =~ s/::/-/g;
  $log_file_name = "$PMBPLogDirName/@{[time]}-$log_file_name.log";
  mkdir_for_file $log_file_name;
  copy_file $file_name => $log_file_name or 
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

sub info_log_file ($$$) {
  my ($level, $file_name, $label) = @_;
  open my $file, '<', $file_name or info_die "$0: $file_name: $!";
  local $/ = undef;
  my $content = <$file>;
  info $level, "";
  info $level, "========== Start - $label ==========";
  info $level, $content;
  info $level, "========== End - $label ==========";
  info $level, "";
  return $content;
} # info_log_file

sub create_temp_dir_name () {
  use_perl_core_module 'File::Temp';
  return File::Temp::tempdir ('PMBP-XX'.'XX'.'XX', TMPDIR => 1, CLEANUP => 1);
} # create_temp_dir_name

our $HasFileTemp = 1;
my $CommonTempDirName;
sub create_temp_file_name () {
  {
    local $HasFileTemp = 0;
    use_perl_core_module 'File::Temp';
  }
  $CommonTempDirName ||= create_temp_dir_name;
  return "$CommonTempDirName/temp-" . rand;
} # create_temp_file_name

## ------ Commands ------

sub _quote_dq ($) {
  my $s = shift;
  $s = '' unless defined $s;
  $s =~ s/\"/\\\"/g;
  return $s;
} # _quote_dq

sub shellarg ($);
if ($PlatformIsWindows) {
  *shellarg = sub ($) {
    ## <https://d.hatena.ne.jp/thinca/20100210/1265813598>
    my $s = $_[0];
    $s =~ s/([&|<>()^"%])/^$1/g;
    $s =~ s/(\\+)"/$1$1"/g;
    $s =~ s/\\^"/\\^"/g;
    return qq{^"$s^"};
  };
} else {
  *shellarg = sub ($) { return quotemeta $_[0] };
}

sub shellcommand ($) {
  if ($PlatformIsWindows and $_[0] =~ /\A[0-9A-Za-z_\\:-]+\z/) {
    return $_[0];
  } else {
    return shellarg $_[0];
  }
} # shellcommand

my $CommandID = 0;
sub run_command ($;%) {
  my ($command, %args) = @_;
  my $id = ++$CommandID;
  local $_;
  my $prefix = defined $args{prefix} ? $args{prefix} : '';
  my $prefix0 = '';
  $prefix0 .= (length $prefix ? ':' : '') . $args{chdir} if defined $args{chdir};
  $prefix = "$id: $prefix";
  my $envs = $args{envs} || {};
  {
    no warnings 'uninitialized';
    info ((defined $args{info_command_level} ? $args{info_command_level} : 2),
          qq{$prefix$prefix0\$ @{[map { $_ . '="' . (_quote_dq $envs->{$_}) . '" ' } sort { $a cmp $b } keys %$envs]}@$command});
  }
  my $stderr_file_name;
  if ($args{discard_stderr} or $PlatformIsWindows) { # instead of 2>&1 on Windows
    if ($HasFileTemp) {
      $stderr_file_name = $args{"2>"} = create_temp_file_name;
    } else {
      $args{"2>"} = sub {};
    }
  }
  local %ENV = map { defined $_ ? $_ : '' } (%ENV, %$envs);
  my $full_command = 
      (defined $args{chdir} ? "cd @{[shellarg $args{chdir}]} && " : "") .
      (defined $args{stdin_value} ? "echo @{[shellarg $args{stdin_value}]}" : '') .
      (join ' ',
         (@$command ? shellcommand $command->[0] : ()),
         map { shellarg $_ } @$command[1..$#$command]) .
      (defined $args{"2>"} ? ' 2> ' . shellarg $args{"2>"} : ' 2>&1') .
      (defined $args{">"} ? ' > ' . shellarg $args{">"} : '') .
      (($args{accept_input} || defined $args{stdin_value}) ? '' : $PlatformIsWindows ? '< NUL' : ' < /dev/null');
  info 10, "$id: Run shell command: |$full_command|";
  profiler_start ($args{profiler_name} || 'command');
  my $pid = open my $cmd, "-|", $full_command
      or info_die "$0: $id: $command->[0]: $!";
  if (defined $args{'$$'}) {
    ${$args{'$$'}} = $pid;
  }
  while (<$cmd>) {
    my $level = defined $args{info_level} ? $args{info_level} : 1;
    $level = $args{onoutput}->($_) if $args{onoutput};
    info $level, "$prefix$_";
  }
  my $return = close $cmd;
  if ($args{'$?'}) {
    ${$args{'$?'}} = $?;
  }
  info 10, "$id: Done (@{[$? >> 8]})";
  profiler_stop ($args{profiler_name} || 'command');
  if (defined $stderr_file_name and -f $stderr_file_name) {
    my $log = info_log_file 3, $stderr_file_name => 'stderr';
    if ($args{onstderr}) {
      local $_ = $log;
      $args{onstderr}->();
    }
  }
  return $return;
} # run_command

## ------ Downloading ------

sub install_system_packages ($;%);

my $HasWget;
my $HasCurl;
sub _save_url {
  my ($url => $file_name, %args) = @_;

  if (defined $args{max_age}) {
    return 1 if -f $file_name and -s $file_name and
        [stat $file_name]->[9] + $args{max_age} > time;
  }

  my $fetcher;
  for (0..1) {
    $HasWget = which_or_version ($WgetCommand) ? 1 : 0 if not defined $HasWget;
    $HasCurl = which_or_version ($CurlCommand) ? 1 : 0 if not defined $HasCurl;
    if ($HasCurl) {
      $fetcher = 'curl';
      last;
    } elsif ($HasWget) {
      $fetcher = 'wget';
      last;
    } else {
      if (install_system_packages [{name => 'curl'}]) {
        undef $HasWget;
        undef $HasCurl;
        next;
      }
    }
    info 0, "There is no |wget| or |curl|";
    return 0;
  }

  mkdir_for_file $file_name;
  info 1, "Downloading <$url>...";
  for (0..$DownloadRetryCount) {
    info 1, "Retrying download ($_/$DownloadRetryCount)...";
    my @option;
    if ($fetcher eq 'wget') {
      @option = (
        $WgetCommand,
        @WgetOption,
        '-O', $file_name,
        ($args{save_response_headers} ? '--save-headers' : ()),
        ($args{timeout} ? '--timeout=' . $args{timeout} : ()),
        '--tries=' . ($args{tries} || 3),
        ($args{max_redirect} ? '--max_redirect=' . $args{max_redirect} : ()),
        (map {
          ('--header' => $_->[0] . ': ' . $_->[1]);
        } @{$args{request_headers} or []}),
        $url,
      );
    } elsif ($fetcher eq 'curl') {
      @option = (
        $CurlCommand,
        @CurlOption,
        '-s', '-S', '-L', '-f',
        '-o', $file_name,
        ($args{save_response_headers} ? ('-D', '-') : ()), # XXX not work as intended
        ($args{timeout} ? ('--max-time', $args{timeout}) : ()),
        '--retry', ($args{tries} || 3),
        ($args{max_redirect} ? ('--max-redirs', $args{max_redirect}) : ()),
        (map {
          ('--header' => $_->[0] . ': ' . $_->[1]);
        } @{$args{request_headers} or []}),
        $url,
      );
    }
    my $result = run_command
        \@option,
        info_level => 2,
        profiler_name => 'network',
        prefix => "$fetcher($_/$DownloadRetryCount): ";
    return 1 if $result && -f $file_name;
  }
  return 0;
} # _save_url

sub save_url ($$;%) {
  if (ref $_[0] eq 'ARRAY') {
    info_die "URL list is empty" unless @{$_[0]};
    my $urls = shift;
    for (@$urls) {
      _save_url ($_, @_) and return $_;
    }
    info_die "Failed to download |@$urls|";
  } else {
    info_die "Not an absolute URL: <$_[0]>"
        unless $_[0] =~ m{^(?:https?|ftp):}i;
    _save_url (@_) or info_die "Failed to download <$_[0]>";
    return $_[0];
  }
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
  profiler_start 'file';
  open my $file, '<', $_[0] or info_die "$0: $_[0]: $!";
  local $/ = undef;
  my $json = decode_json (<$file>);
  close $file;
  profiler_stop 'file';
  return $json;
} # load_json

sub load_json_after_garbage ($) {
  profiler_start 'file';
  open my $file, '<', $_[0] or info_die "$0: $_[0]: $!";
  local $/ = undef;
  my $data = <$file>;
  close $file;
  profiler_stop 'file';
  if ($data =~ s{^(.*)\n\[}{[}s) {
    my $garbage = $1;
    my $json = decode_json ($data);
    return ($garbage, $json);
  } else {
    return ($data, undef);
  }
} # load_json_after_garbage

## ------ Mac OS X ------

sub xcode_select_install () {
  info_die "|xcode-select --install| is requested on non-Mac platform"
      unless $PlatformIsMacOSX;

  return run_system_commands
      ([[{}, ['xcode-select', '--install'],
         'Installing Xcode command line developer tools', sub { },
         'packagemanager']]);
} # xcode_select_install

sub install_homebrew () {
  ## Homebrew and Homebrew-Cask
  ## <https://docs.brew.sh/Installation.html>

  # requires xcode_select_install

  my $temp_file_name = "$PMBPDirName/tmp/homebrewinstall";
  save_url
      q<https://raw.githubusercontent.com/Homebrew/install/master/install> =>
      $temp_file_name,
      max_age => 24*60*60;
  run_system_commands ([[{}, ['/usr/bin/ruby', $temp_file_name],
                         'Installing homebrew', sub { }, 'packagemanager']])
      ## The installer requests for input if there is tty.
      or info_die "Failed to install homebrew";
} # install_homebrew

## ------ System environment (platform independent) ------

{
  my $HasSudo;
  sub wrap_by_sudo ($) {
    my $cmd = $_[0];
    $HasSudo = which_or_version ($SudoCommand) unless defined $HasSudo;
    if ($HasSudo) {
      return [$SudoCommand, '--', @$cmd];
    } else {
      return ['su', '-c', join ' ', map { shellarg $_ } @$cmd];
    }
  } # wrap_by_sudo
}

sub run_system_commands ($) {
  my $commands = $_[0];
  ## Array reference of
  ##   Array reference:
  ##     0  Hash reference of environment variables
  ##     1  Array reference of command and arguments
  ##     2  Info text before start, if any, or |undef|
  ##     3  Code reference invoked after success

  unless ($ExecuteSystemPackageInstaller) {
    info 0, "Execute following command and retry:";
    info 0, '';
    my @c;
    for my $c (@$commands) {
      push @c, join ' ',
          (grep { length $_ } join ' ', map { shellarg ($_) . '=' .shellarg $c->[0]->{$_} } keys %{$c->[0]}),
          (join ' ', map { shellarg $_ } @{$c->[1]});
    }
    info 0, '  $ ' . join " && \\\n    ", @c;
    info 0, '';
    return 0;
  } else {
    for my $c (@$commands) {
      my ($envs, $cmd, $label, $done, $pn) = @$c;
      info 0, "$label..." if defined $label;
      my $result = run_command $cmd,
          envs => $envs,
          info_level => 1,
          info_command_level => 1,
          profiler_name => $pn;
      if ($result) {
        $done->();
      } else {
        return 0;
      }
    }
    return 1;
  }
} # run_system_commands

{
  my $HasAPT;
  my $HasYUM;
  my $HasBrew;

  sub install_which () {
    ## CentOS: |which|
    ## Debian: |debianutils|
    
    if (run_command [$YumCommand, '--version']) {
      $HasYUM = 1;
      return run_system_commands
          [[{}, ['su', '-c', join ' ', map { shellarg $_ }
                 $YumCommand, 'install', '-y', 'which'],
            'Installing which', sub { }, 'packagemanager']];
    }

    return 0;
  } # install_which

  sub system_package_manager () {
    $HasAPT = which_or_version ($AptGetCommand) ? 1 : 0
        if not defined $HasAPT;
    $HasYUM = which_or_version ($YumCommand) ? 1 : 0
        if not defined $HasYUM;

    if (not $HasAPT and not $HasYUM and not defined $HasBrew) {
      $HasBrew = which ($BrewCommand) ? 1 : 0;
      if (not $HasBrew and $PlatformIsMacOSX) {
        install_homebrew;
        $HasBrew = which ($BrewCommand) ? 1 : 0;
      }
    }

    return $HasAPT ? 'apt' : $HasYUM ? 'yum' : $HasBrew ? 'brew' : 'nopackagemanager';
  } # system_package_manager
}

{
  my $AptGetUpdated;
  sub construct_install_system_packages_commands ($;%) {
    my ($packages, %args) = @_;

    my $pm = system_package_manager;
    
    my @command;
    if ($pm eq 'apt') {
      my @name = map { $_->{debian_name} || $_->{name} } @$packages;

      for (@{$args{before_apt} or []}) {
        push @command, @{$_->()};
      }
      
      unless ($AptGetUpdated) {
        for (@name) {
          my $result = '';
          my $ok = run_command ['apt-cache', 'show', $_],
              onoutput => sub { $result .= $_[0]; 2 };
          unless ($ok and $result =~ m{^\Q$_\E }m) {
            push @command, [{}, wrap_by_sudo [$AptGetCommand, 'update'],
                            undef, sub { $AptGetUpdated = 1 }, 'network'];
            last;
          }
        }
      }
      
      push @command, [
        {DEBIAN_FRONTEND => "noninteractive"},
        wrap_by_sudo [$AptGetCommand, 'install', '-y', @name],
        "Installing @name",
        sub { }, 'packagemanager',
      ];
    } elsif ($pm eq 'yum') {
      for (@{$args{before_yum} or []}) {
        push @command, @{$_->()};
      }
      
      my @name = map { $_->{redhat_name} || $_->{name} } @$packages;
      push @command, [{}, wrap_by_sudo [$YumCommand, 'install', '-y', @name],
                      "Installing @name", sub { }, 'packagemanager'];
    } elsif ($pm eq 'brew') {
      my @name;
      my @cask_name;
      for (@$packages) {
        if (defined $_->{cask_name}) {
          push @cask_name, $_->{cask_name};
        } else {
          push @name, $_->{homebrew_name} || $_->{name};
          }
      }
      if (@name) {
        push @command, [{}, [$BrewCommand, 'install', @name],
                        "Installing @name", sub { }, 'packagemanager'];
      }
      if (grep { 'openssl' eq $_ } @name) {
        push @command,
            [{}, [$BrewCommand, 'link', 'openssl', '--force'], undef, sub { },
             'packagemanager'];
      }
      if (@cask_name) {
        ## Old
        #push @command, [{}, [$BrewCommand, 'cask', 'install', @cask_name],
        #                "Installing @cask_name", sub { }, 'packagemanager'];
        push @command, [{}, [$BrewCommand, 'install', '--cask', @cask_name],
                        "Installing @cask_name", sub { }, 'packagemanager'];
      }

      for (@{$args{after_brew} or []}) {
        push @command, @{$_->()};
      }
    }
    return \@command;
  } # construct_install_system_packages_commands
}

sub install_system_packages ($;%) {
  my ($packages, %args) = @_;
  return unless @$packages;

  my $commands = construct_install_system_packages_commands $packages, %args;
  if (@$commands) {
    return run_system_commands $commands;
  } else {
    info 0, "Install following packages and retry:";
    info 0, '';
    info 0, "  " . join ' ', map { $_->{name} } @$packages;
    info 0, '';
    return 0;
  }
} # install_system_packages

sub use_perl_core_module ($) {
  my $package = $_[0];
  eval qq{ require $package } and return;

  my $sys = {
    'File::Path' => {name => 'perl-File-Path', debian_name => 'libfile-path-perl'},
    'File::Copy' => {name => 'perl-File-Copy', debian_name => 'libfile-copy-perl'},
    'File::Temp' => {name => 'perl-File-Temp', debian_name => 'libfile-temp-perl'},
    'Digest::MD5' => {name => 'perl-Digest-MD5', debian_name => 'libdigest-md5-perl'}, # core 5.7.3+
    'PerlIO' => {name => 'perl-PerlIO', redhat_name => 'perl(PerlIO)', debian_name => 'perl-modules'}, # core 5.7.3+
  }->{$package} or die "Package info for |$package| not defined";

  install_system_packages [$sys]; # or die at require

  eval qq{ require $package } or die $@; # not info_die
} # use_perl_core_module

{
  sub get_perlbrew_perl_bin_dir_name ($) {
    my $perl_version = shift;
    return "$RootDirName/local/perlbrew/perls/perl-$perl_version/bin";
  } # get_perlbrew_perl_bin_dir_name

  my $EnvPath = {};
  sub get_env_path ($) {
    my $perl_version = shift;
    return $EnvPath->{$perl_version} ||= do {
      my $perl_path = get_perlbrew_perl_bin_dir_name $perl_version;
      my $pm_path = get_pm_dir_name ($perl_version) . "/bin";
      my $common_bin_path = "$RootDirName/local/common/bin";
      my $sep = $PlatformIsWindows ? ';' : ':';
      join $sep, $pm_path, $perl_path, $common_bin_path, $ENV{PATH};
    };
  } # get_env_path

  my $HasWhich;
  sub which ($;$);
  sub which ($;$) {
    my ($command, $perl_version) = @_;

    unless (defined $HasWhich) {
      if (run_command [$WhichCommand, 'which']) {
        $HasWhich = 1;
      } else {
        $HasWhich = install_which;
      }
    }
    
    my $output;
    if (run_command [$WhichCommand, $command],
            envs => {defined $perl_version ? (PATH => get_env_path ($perl_version)) : ()},
            discard_stderr => 1,
            onoutput => sub { $output = $_[0]; 3 }) {
      $output =~ s/[\x20\x0D\x0A]+\z//;
      if (defined $output and
          $output =~ m{^(.*\Q$command\E(?:\.[A-Za-z0-9]+|))$}i) {
        info 10, "Result is: |$1|";
        return $1;
      } else {
        info 10, "|which| output |$output| does not contain the result";
      }
    }
    return undef;
  } # which

  sub which_or_version ($) {
    my $cmd = $_[0];
    my $result = which $cmd;
    if ($result) {
      return $result;
    } elsif (run_command [$cmd, '--version']) {
      return 1;
    } else {
      return 0;
    }
  } # which_or_version
}

my $CommandDefs = {};

$CommandDefs->{make} = {
  bin => 'make',
  packages => [
    ($PlatformIsMacOSX ? (
      {name => 'homebrew/dupes/xar'},
    ) : ()),
    {name => 'make',
     homebrew_name => 'homebrew/dupes/make'},
  ],
};

$CommandDefs->{gcc} = {
  bin => 'gcc',
  packages => [{name => 'gcc'}],
};

$CommandDefs->{'g++'} = {
  bin => 'g++',
  packages => [{name => 'g++', redhat_name => 'gcc-c++'}],
};

$CommandDefs->{tar} = {
  bin => 'tar',
  packages => [{name => 'tar'}],
};

$CommandDefs->{bzip2} = {
  bin => 'bzip2',
  packages => [{name => 'bzip2'}],
};

$CommandDefs->{git} = {
  bin => 'git',
  packages => [{name => 'git'}],
};

$CommandDefs->{curl} = {
  bin => 'curl',
  packages => [{name => 'curl'}],
};

$CommandDefs->{wget} = {
  bin => 'wget',
  packages => [{name => 'wget'}],
};

$CommandDefs->{mysqld} = {
  bin => ['mysqld', '/usr/sbin/mysqld'],
  packages => [
    {name => 'mysql-server-devel',
     #redhat_name => 'MySQL-devel',
     redhat_name => 'mariadb-devel',
     #debian_name => 'libmysqld-dev',
     debian_name => 'libmariadbd-dev',
     homebrew_name => 'mysql'},
    {name => 'mysql-server-devel',
     #redhat_name => 'MySQL-devel',
     redhat_name => 'mariadb-devel',
     debian_name => 'mariadb-server',
     homebrew_name => 'mysql'},
  ],
};

$CommandDefs->{'mysql-client'} = {
  bin => 'mysql',
  packages => [
    {name => 'mysql-client',
     redhat_name => 'MariaDB-client',
     #debian_name => 'mysql-client',
     debian_name => 'default-mysql-client',
     homebrew_name => 'mysql'},
  ],
};

$CommandDefs->{'ssh-keygen'} = {
  bin => 'ssh-keygen',
  packages => [
    {name => 'openssh-client',
     #redhat_name => '',
     #debian_name => '',
     homebrew_name => 'openssh'},
  ],
};

$CommandDefs->{vim} = {
  bin => 'vim',
  packages => [{name => 'vim', redhat_name => 'vim-common'}],
};

$CommandDefs->{docker} = {
  bin => 'docker',
  #check_command => ['docker', 'stack'],
  before_apt => \&before_apt_for_docker,
  before_yum => \&before_yum_for_docker,
  after_brew => \&after_brew_for_docker,
  packages => [{name => 'docker-ce', cask_name => 'docker'}],
};

$CommandDefs->{gnuplot} = {
  bin => 'gnuplot',
  packages => [{name => 'gnuplot'}],
};

sub install_commands ($) {
  my @package;
  my %found;
  my @before_apt;
  my @before_yum;
  my @after_brew;
  ITEM: for my $item (grep { not $found{$_}++ } @{$_[0]}) {
    my $def = $CommandDefs->{$item};
    info_die "Command |$item| is not defined" unless defined $def;

    if (defined $def->{check_command}) {
      if (run_command $def->{check_command}, info_level => 9) {
        info 2, "You have command |$item|";
        next ITEM;
      }
    } elsif (defined $def->{bin}) {
      for (ref $def->{bin} ? @{$def->{bin}} : $def->{bin}) {
        my $which = which $_;
        if (defined $which) {
          info 2, "You have command |$item| at |$which|";
          next ITEM;
        }
      }
    }

    push @package,
        @{$def->{packages} || info_die "|packages| not defined for command |$item|"};
    push @before_apt, $def->{before_apt} if defined $def->{before_apt};
    push @before_yum, $def->{before_yum} if defined $def->{before_yum};
    push @after_brew, $def->{after_brew} if defined $def->{after_brew};
  } # ITEM

  if (@package) {
    install_system_packages
        (\@package,
         before_apt => \@before_apt,
         before_yum => \@before_yum,
         after_brew => \@after_brew)
        or info_die "Can't install |@{$_[0]}|";
  }

  if ($found{docker}) {
    my $pm = system_package_manager;
    if ($pm eq 'brew' and not which 'docker') {
      my $count = 0;
      info 0, "Waiting for Docker for Mac installed...";
      while (not which 'docker') {
        sleep 3;
        $count++;
        if ($count > 30) {
          info_die "Docker for Mac is still not ready";
        }
      }
    }
  } # docker
} # install_commands

## ------ Git repositories ------

{
  my $HasGit;
  sub git () {
    my $git_command = $GitCommand;
    $git_command = 'git' unless defined $git_command;
    $HasGit = which_or_version $git_command unless defined $HasGit;
    if (not $HasGit) {
      if ($git_command eq 'git') {
        install_system_packages [{name => 'git'}]
            or info_die "Can't run |$git_command|";
      } else {
        info_die "Can't run |$git_command|";
      }
    }
    return $git_command;
  } # git
}

sub init_git_repository ($) {
  my $repo_dir_name = $_[0];
  make_path $repo_dir_name;
  unless (-f "$repo_dir_name/.git/config") {
    run_command [git, 'init'],
        chdir => $repo_dir_name
            or info_die "Can't run |git init|";
  }
} # init_git_repository

sub read_gitignore ($) {
  my $file_name = shift;
  return undef unless -f $file_name;
  profiler_start 'file';
  open my $file, '<', $file_name or info_die "$0: $file_name: $!";
  my @ignore = map { chomp; $_ } grep { length } <$file>;
  profiler_stop 'file';
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

sub git_submodules ($) {
  my ($git_dir_name) = @_;
  my $out = '';
  #run_command
  #    [git, 'submodule', '--quiet', 'foreach', 'sh', '-c', 'true; echo $path'],
  #    chdir => $git_dir_name,
  #    onoutput => sub { $out .= $_[0]; 6 }
  #        or info_die "git submodule failed";
  #return [map { +{dir_name => $_} } grep { length } split /\x0A/, $out];
  return [] unless -f "$git_dir_name/.gitmodules";
  run_command
      [git, 'config', '-f', '.gitmodules',
       '--get-regexp', '^submodule\..+\.url$'],
      chdir => $git_dir_name,
      onoutput => sub { $out .= $_[0]; 6 };
  # fail if no .gitmodules, no submodule in .gitmodules, or not in git repo
  my @r;
  for (split /\x0A/, $out) {
    if (m{^submodule\.(\S+)\.url\s+(.+)$}) {
      push @r, {dir_name => $1, url => $2};
    }
  }
  return \@r;
} # git_submodules

sub git_submodule_url ($$) {
  my ($git_dir_name, $submodule_dir_name) = @_;
  my $out = '';
  run_command
      [git, 'config', '-f', '.gitmodules', "submodule.$submodule_dir_name.url"],
      chdir => $git_dir_name,
      onoutput => sub { $out .= $_[0]; 6 }
          or info_die "git config failed";
  chomp $out if defined $out;
  return length $out ? $out : undef;
} # git_submodule_url

sub add_git_submodule ($$;%);
sub add_git_submodule ($$;%) {
  my ($git_dir_name, $url, %args) = @_;
  my $default_parent = 'modules';
  my $parent = $args{parent_dir_name};
  $parent = $default_parent if not defined $parent;
  my $dir_name = [grep { length } split m{/}, $url]->[-1];
  $dir_name =~ s/\.git$//;
  $dir_name =~ s/^perl-//;
  for my $submodule (grep { $_->{dir_name} =~ m{^(?:\Q$parent\E|\Q$default_parent\E)/} } @{git_submodules $git_dir_name}) {
    if ($submodule->{url} eq $url) {
      info 5, "$git_dir_name: submodule <$url> is already added as |$submodule->{dir_name}|";
      if ($args{recursive} and $args{top_level}) {
        for my $submodule (grep { $_->{dir_name} =~ m{^modules/} } @{git_submodules "$git_dir_name/$submodule->{dir_name}"}) {
          add_git_submodule $git_dir_name, $submodule->{url}, recursive => $args{recursive}, parent_dir_name => $parent;
        }
      }
      return undef;
    }
  }
  if (-e "$git_dir_name/$parent/$dir_name") {
    my $i = 2;
    {
      if (-e "$git_dir_name/$parent/$dir_name.$i") {
        $i++;
        redo;
      }
      $dir_name = "$dir_name.$i";
    }
  }
  info 0, "Adding <$url> as a submodule...";
  run_command
      [git, 'submodule', 'add', $url, "$parent/$dir_name"],
      chdir => $git_dir_name
          or info_die "git submodule failed";
  my $extra_file_name = "$git_dir_name/$parent/$dir_name/config/perl/pmbp-extra-modules.txt";
  if (-f $extra_file_name) {
    open my $extra_file, '<', $extra_file_name
        or info_die "Can't open |$extra_file_name|: $!";
    local $/ = undef;
    my @modules;
    for (split /\x0D?\x0A/, <$extra_file>) {
      if (/^\s*#/) {
        #
      } elsif (/^(\S+)$/) {
        push @modules, $1;
      }
    }
    if (@modules) {
      my $excluded_file_name = "$git_dir_name/config/perl/pmbp-exclusions.txt";
      my $rel_module_name = File::Spec->abs2rel
          ("$git_dir_name/$parent/$dir_name", "$git_dir_name/config/perl");
      make_path "$git_dir_name/config/perl";
      open my $excluded_file, '>>', $excluded_file_name
          or info_die "Can't append to |$excluded_file_name|: $!";
      print $excluded_file qq{\n- "$rel_module_name" @modules};
      close $excluded_file;
    }
  }
  if ($args{recursive}) {
    for my $submodule (grep { $_->{dir_name} =~ m{^modules/} } @{git_submodules "$git_dir_name/$parent/$dir_name"}) {
      add_git_submodule $git_dir_name, $submodule->{url}, recursive => $args{recursive}, parent_dir_name => $parent;
    }
  }
  return "$parent/$dir_name";
} # add_git_submodule

## ------ Perl ------

{
  my $LatestPerlVersion;
  sub get_latest_perl_version () {
    return $LatestPerlVersion if $LatestPerlVersion;

    my $file_name = qq<$PMBPDirName/latest-perl-version.txt>;
    save_url q<https://raw.githubusercontent.com/wakaba/perl-setupenv/master/version/perl.txt> => $file_name,
        max_age => 24*60*60;
    open my $file, '<', $file_name or info_die "Failed to open |$file_name|";
    $LatestPerlVersion = <$file>;
  } # get_latest_perl_version
}

sub get_perl_version ($) {
  my $perl_command = shift;
  my $perl_version;
  run_command [$perl_command, '-e', 'printf "%vd", $^V'],
      discard_stderr => 1,
      onoutput => sub { $perl_version = $_[0]; 2 };
  $perl_version =~ s/^v//;
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

{
  my $CPANTopURL;
  sub get_cpan_top_url () {
    return $CPANTopURL ||= save_url [
      qw<
        https://www.cpan.org/
        https://ftp.riken.jp/lang/CPAN/
        https://ftp.yz.yamagata-u.ac.jp/pub/lang/cpan/
        https://ftp.jaist.ac.jp/pub/CPAN/
      >,
      #http://ftp.nara.wide.ad.jp/pub/CPAN/
      #http://cpan.cpantesters.org/
      #http://www.perl.com/CPAN/
      #http://search.cpan.org/CPAN/
      #http://www.cpan.dk/
    ] => "$PMBPDirName/tmp/cpan-top", max_redirect => 0, timeout => 5, tries => 1;
  } # get_cpan_top_url
}

sub get_perlbrew_envs () {
  return {PERLBREW_ROOT => (abs_path "$RootDirName/local/perlbrew"),
          PERLBREW_CPAN_MIRROR => get_cpan_top_url,
          PERL5LIB => (abs_path "$RootDirName/local/perlbrew-lib")}
} # get_perlbrew_envs

sub install_perlbrew () {
  return if -s "$RootDirName/local/perlbrew/bin/perlbrew" and
            -s "$RootDirName/local/perlbrew/bin/patchperl" and
            -s "$RootDirName/local/perlbrew/bin/patchperl.main" and
            -s ("$RootDirName/local/perlbrew/bin/patchperl") < (-s "$RootDirName/local/perlbrew/bin/patchperl.main") and
            -s "$RootDirName/local/perlbrew/pmbp-perlbrew-v2";
  make_path "$RootDirName/local/perlbrew";

  use_perl_core_module 'PerlIO';

  install_commands ['bzip2', 'make', 'gcc'];

  my $install_file_name = "$RootDirName/local/install.perlbrew";
  save_url $PerlbrewInstallerURL => $install_file_name;

  local $/ = undef;
  open my $install_file, '<', $install_file_name or die "$0: $install_file_name: $!";
  my $installer = <$install_file>;
  $installer =~ s{https://raw.github.com/}{https://raw.githubusercontent.com/}g;
  open $install_file, '>', $install_file_name or die "$0: $install_file_name: $!";
  print $install_file $installer;
  close $install_file;

  run_command
      ['bash', $install_file_name],
      envs => get_perlbrew_envs;
  my $perlbrew_file_name = "$RootDirName/local/perlbrew/bin/perlbrew";
  unless (-f $perlbrew_file_name) {
    info_die "Can't install perlbrew";
  }

  {
    my $script = do {
      open my $file, '<', $perlbrew_file_name
        or info_die "$perlbrew_file_name: $!";
      local $/ = undef;
      <$file>;
    };
    my $cpan_top = get_cpan_top_url;
    $script =~ s{"https?://www.cpan.org/src/5.0/"}{"${cpan_top}src/5.0/"}g;
    $script =~ s{"https?://www.cpan.org/src/README.html"}{"${cpan_top}src/README.html"}g;
    open my $file, '>', $perlbrew_file_name
        or info_die "$perlbrew_file_name: $!";
    print $file $script;
  }

  ## Core module in Perl 5.9.5+
  ## (IPC::Cmd modified to remove dependency)
  save_url q<https://raw.github.com/wakaba/perl-setupenv/master/lib/perl58perlbrewdeps.pm>
      => "$RootDirName/local/perlbrew/lib/perl5/IPC/Cmd.pm";

  run_command ['mv', "$RootDirName/local/perlbrew/bin/patchperl"
                  => "$RootDirName/local/perlbrew/bin/patchperl.main"]
      or info_die "Can't move $RootDirName/local/perlbrew/bin/patchperl";
  open my $f, '>', "$RootDirName/local/perlbrew/bin/patchperl"
      or info_die "Can't write $RootDirName/local/perlbrew/bin/patchperl: $!";
  print $f qq{\#!/usr/bin/perl
    use lib "@{[abs_path "$RootDirName/local/perlbrew/lib/perl5"]}";
    do "@{[abs_path "$RootDirName/local/perlbrew/bin/patchperl.main"]}";
  };
  close $f;
  run_command ['chmod', 'ugo+x', "$RootDirName/local/perlbrew/bin/patchperl"]
      or info_die "Can't move $RootDirName/local/perlbrew/bin/patchperl";

  open my $file, '>', "$RootDirName/local/perlbrew/pmbp-perlbrew-v2"
      or info_die "$RootDirName/local/perlbrew/pmbp-perlbrew-v2: $!";
} # install_perlbrew

sub install_perl_by_perlbrew ($) {
  my $perl_version = shift;
  install_perlbrew;
  my $i = 0;
  PERLBREW: {
    $i++;
    my $log_file_name;
    my $redo;
    my @perl_option;
    if ($PerlOptions->{relocatable}) {
      push @perl_option, '-D' => 'userelocatableinc'; # can't be used with useshrplib
    } else {
      push @perl_option, '-D' => 'useshrplib'; # required by mod_perl
    }
    run_command ["$RootDirName/local/perlbrew/bin/perlbrew",
                 'install',
                 'perl-' . $perl_version,
                 '--notest',
                 '--as' => 'perl-' . $perl_version,
                 '-j' => $PerlbrewParallelCount,
                 '-A' => 'ccflags=-fPIC',
                 '-D' => 'usethreads',
                 @perl_option,
                ],
                envs => get_perlbrew_envs,
                prefix => "perlbrew($i): ",
                profiler_name => 'perlbrew',
                onoutput => sub {
                  if ($_[0] =~ m{^  tail -f (.+?/perlbrew/build.perl-.+?\.log)}) {
                    $log_file_name = $1;
                    $log_file_name =~ s{^~}{$ENV{HOME}} if defined $ENV{HOME};
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
    
    my $perl_path = "$RootDirName/local/perlbrew/perls/perl-$perl_version/bin/perl";
    if (-f $perl_path) {
      copy_log_file $log_file_name => "perl-$perl_version"
          if defined $log_file_name and $SavePerlbrewLog;

      my $created_libperl = "$RootDirName/local/perlbrew/build/perl-$perl_version/libperl.so";
      my $expected_libperl = "$RootDirName/local/perl-$perl_version/pm/lib/libperl.so";
      if (-f $created_libperl and not -f $expected_libperl) {
        mkdir_for_file $expected_libperl;
        run_command ['cp', $created_libperl => $expected_libperl]
            or info_die "Can't copy libperl.so";
      }
    } else {
      copy_log_file $log_file_name => "perl-$perl_version"
          if defined $log_file_name;
      if ($redo and $i < 10) {
        info 0, "perlbrew($i): Failed to install perl-$perl_version; retrying...";
        redo PERLBREW;
      } else {
        info_die "perlbrew($i): Failed to install perl-$perl_version";
      }
    }
    $PerlCommand = $perl_path;
  } # PERLBREW
} # install_perl_by_perlbrew

sub install_perlbuild () {
  my $perlbuild_path = "$RootDirName/local/perlbuild";
  make_path "$RootDirName/local/perlbrew";
  my $perlbuild_url = q<https://raw.githubusercontent.com/tokuhirom/Perl-Build/master/perl-build>;
  save_url $perlbuild_url => $perlbuild_path, max_age => 60*60*24*30;

  use_perl_core_module 'PerlIO';
} # install_perlbuild;

sub install_perl_by_perlbuild ($) {
  my $perl_version = shift;
  install_perlbuild;
  my $i = 0;
  my $parallel_count = $PerlbrewParallelCount;
  my $tarball_path;
  PERLBREW: {
    $i++;
    my $log_file_name;
    my $redo;
    my @perl_option;
    if ($PerlOptions->{relocatable}) {
      push @perl_option, '-D' => 'userelocatableinc'; # can't be used with useshrplib
    } else {
      push @perl_option, '-D' => 'useshrplib'; # required by mod_perl
    }
    my $perl_dir_path = "$RootDirName/local/perlbrew/perls/perl-$perl_version";
    my $perl_path = "$perl_dir_path/bin/perl";
    my $perl_tar_dir_path = pmtar_dir_name () . '/perl';
    my @patch;

    if ($PlatformIsMacOSX) {
      make_path "$RootDirName/local/perlbrew-lib/Devel/PatchPerl/Plugin";
      save_url "https://raw.githubusercontent.com/wakaba/perl-setupenv/master/lib/Devel/PatchPerl/Plugin/MacOSX.pm" => "$RootDirName/local/perlbrew-lib/Devel/PatchPerl/Plugin/MacOSX.pm",
          max_age => 10*24*60*60;
      push @patch, qw(MacOSX);
    }

    make_path $perl_tar_dir_path;
    my $output = '';
    run_command ['perl',
                 "$RootDirName/local/perlbuild",
                 (defined $tarball_path ? $tarball_path : $perl_version),
                 $perl_dir_path,
                 '-j' => $parallel_count,
                 '-A' => 'ccflags=-fPIC',
                 '-D' => 'usethreads',
                 (map { ('--patches' => $_) } @patch),
                 '--noman',
                 '--tarball-dir' => $perl_tar_dir_path,
                 @perl_option,
                ],
                envs => get_perlbrew_envs,
                onoutput => sub { $output .= $_[0]; 2 },
                prefix => "perlbuild($i): ",
                profiler_name => 'perlbuild'
                    unless -f $perl_path;
    
    if (-f $perl_path) {
      my $created_libperl = "$RootDirName/local/perlbrew/build/perl-$perl_version/libperl.so";
      my $expected_libperl = "$RootDirName/local/perl-$perl_version/pm/lib/libperl.so";
      if (-f $created_libperl and not -f $expected_libperl) {
        mkdir_for_file $expected_libperl;
        run_command ['cp', $created_libperl => $expected_libperl]
            or info_die "Can't copy libperl.so";
      }
    } else { # perl not installed
      ## perl-build error message sniffing
      my @required_installable;
      if ($output =~ m{^I can't find make or gmake, and my life depends on it.}m) {
        push @required_installable, 'make';
        $redo = 1;
      } elsif ($output =~ m{^You need to find a working C compiler.}m) {
        push @required_installable, 'gcc';
        $redo = 1;
      }

      if (@required_installable) {
        install_commands \@required_installable;
        $redo = 1;
      }
      
      if ($output =~ m{Cannot get file from (https?://.+?/([a-z][a-zA-Z0-9_.-]+?\.tar\.gz)): 599 Internal Exception}) {
        ## HTTP GET timeout
        $tarball_path = "$perl_tar_dir_path/$2";
        save_url "$1" => $tarball_path;
        $redo = 1;
      }
      ## Workaround for unstable platforms (e.g. Mac OS X)
      if (not $redo and $parallel_count != 1) {
        $parallel_count = 1;
        $redo = 1;
      }
      if ($redo and $i < 10) {
        info 0, "perlbuild($i): Failed to install perl-$perl_version; retrying...";
        redo PERLBREW;
      } else {
        info_die "perlbuild($i): Failed to install perl-$perl_version";
      }
    }
    $PerlCommand = $perl_path;
  } # PERLBREW
} # install_perl_by_perlbuild

sub install_perl ($) {
  if ($PlatformIsWindows) {
    info_die "|install-perl| is not supported on Windows";
  }
  return install_perl_by_perlbuild ($_[0]);
} # install_perl

sub create_perlbrew_perl_latest_symlink ($) {
  my $perl_version = shift;
  return unless -d "$RootDirName/local/perlbrew/perls/perl-$perl_version";

  run_command ['rm', '-f', "$RootDirName/local/perl-latest"];
  run_command ['ln', '-s', "perl-$perl_version", "perl-latest"],
      chdir => "$RootDirName/local";

  make_path "$RootDirName/local/perlbrew/perls";
  run_command ['rm', '-f', "$RootDirName/local/perlbrew/perls/perl-latest"];
  run_command ['ln', '-s', "perl-$perl_version", "perl-latest"],
      chdir => "$RootDirName/local/perlbrew/perls";
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
        $PerlVersionChecked->{$path, $perl_command} = 1;
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

  sub get_perl_core_lib_paths ($$) {
    my ($perl_command, $perl_version) = @_;
    return (
      (get_perl_config $perl_command, $perl_version, 'privlibexp'),
      (get_perl_config $perl_command, $perl_version, 'archlibexp'),
    );
  } # get_perl_core_lib_paths
}

sub install_cpan_config ($$$) {
  my ($perl_command, $perl_version, $perl_lib_dir_name) = @_;
  return run_command
      [$perl_command, '-MCPAN', '-MCPAN::HandleConfig',
       '-e' => q{CPAN::HandleConfig->load; CPAN::HandleConfig->commit}],
      envs => {LANG => 'C',
               PATH => get_env_path ($perl_version),
               HOME => get_cpanm_dummy_home_dir_name ($perl_lib_dir_name)},
      stdin_value => "yes\n";
} # install_cpan_config

## ------ cpanm ------

sub install_cpanm () {
  if (not -f $CPANMCommand or
      [stat $CPANMCommand]->[9] < [stat $0]->[9]) { # mtime
    unless (run_command ['perl', '-MExtUtils::MakeMaker', '-e', ' ']) { # core 5+
      install_system_packages [{name => 'perl-ExtUtils-MakeMaker', debian_name => 'perl-modules'}] or # debian
      install_system_packages [{name => 'perl-ExtUtils-MakeMaker', debian_name => 'libextutils-makemaker-perl'}] # old Debian
          or info_die "Your perl does not have |ExtUtils::MakeMaker| (which is a core module)";
    }

    save_url $CPANMURL => $CPANMCommand;
  }
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

    require JSON::PP;
    my $orig_jsonpp = \&JSON::PP::new;
    *JSON::PP::new = sub {
      return $orig_jsonpp->(@_)->allow_blessed;
    };

    sub CPAN::Meta::TO_JSON { undef }

    my $orig_unsatisfied_deps = \&App::cpanminus::script::unsatisfied_deps;
    *App::cpanminus::script::unsatisfied_deps = sub {
      if ($_[0]->{scandeps}) {
        return ();
      } else {
        return $orig_unsatisfied_deps->(@_);
      }
    };

    ## To support "Checking if you have ExtUtils::MakeMaker 7.0401 ... Yes (7.04_01)":-<
    my $orig_accepts = \&CPAN::Meta::Requirements::_Range::Range::_accepts;
    *CPAN::Meta::Requirements::_Range::Range::_accepts = sub {
      my ($self, $version) = @_;
      return 1 if $orig_accepts->(@_);
      if (defined $self->{minimum} and
          not defined $self->{maximum} and not defined $self->{exclusions}) {
        my $min = $self->{minimum};
        $min =~ tr/_//d;
        $version =~ tr/_//d;
        return 1 if $min eq $version;
      }
      return;
    }; # _accepts

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

    setpgrp 0, 0 unless $^O eq 'MSWin32';
    
    my $app = App::cpanminus::script->new;
    $app->parse_options (@ARGV);
    exit $app->doit;
  };
  close $file;
  $CPANMWrapperCreated = 1;
} # install_cpanm_wrapper

sub install_makeinstaller ($$;%) {
  my ($name, $configure_args, %args) = @_;
  #return if -f "$MakeInstaller.$name";
  my $makefilepl_args = join ' ', @$configure_args;
  info_writing 1, "makeinstaller.$name", "$MakeInstaller.$name";
  mkdir_for_file "$MakeInstaller.$name";
  open my $file, '>', "$MakeInstaller.$name"
      or info_die "$0: $MakeInstaller.name: $!";
  if ($args{module_build}) {
    printf $file q{#!/bin/bash
      export SHELL="%s"
      (
        if [ -f Build.PL ]; then
          echo perl Build.PL %s && perl Build.PL %s && \
          echo ./Build          && ./Build && \
          echo ./Build install  && ./Build install
        else
          echo perl %s Makefile.PL %s && perl %s Makefile.PL %s && \
          echo make                && make && \
          echo make install        && make install
        fi
      ) || echo "!!! MakeInstaller failed !!!"
    }, _quote_dq $ENV{SHELL},
       $makefilepl_args, $makefilepl_args,
       $args{perl_options} || '',
       $makefilepl_args,
       $args{perl_options} || '',
       $makefilepl_args;
  } else {
    printf $file q{#!/bin/bash
      (
        export SHELL="%s"
        echo perl %s Makefile.PL %s && perl %s Makefile.PL %s && \
        echo make                && make && \
        echo make install        && make install
      ) || echo "!!! MakeInstaller failed !!!"
    }, _quote_dq $ENV{SHELL},
       $args{perl_options} || '',
       $makefilepl_args,
       $args{perl_options} || '',
       $makefilepl_args;
  }
  close $file;
  chmod 0755, "$MakeInstaller.$name";
} # install_makeinstaller

{
  my $CPANMDummyHomeDirNames = {};
  sub get_cpanm_dummy_home_dir_name ($) {
    my $lib_dir_name = shift;
    return $CPANMDummyHomeDirNames->{$lib_dir_name} ||= do {
      ## For Module::Build-based packages (e.g. Class::Accessor::Lvalue)
      use_perl_core_module 'Digest::MD5';
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
our $CPANMInvoked = 0;
sub cpanm ($$);
sub cpanm ($$) {
  my ($args, $modules) = @_;
  my $result = {};

  my $perl_lib_dir_name = $args->{perl_lib_dir_name}
      || (($args->{info} or $args->{version}) ? $CPANMDirName : undef)
      or info_die "No |perl_lib_dir_name| specified";
  my $perl_command = $args->{perl_command} || $PerlCommand;
  my $perl_version = $args->{perl_version}
      || (($args->{info} or $args->{version}) ? (get_perl_version ($perl_command)) : undef)
      or info_die "No |perl_version| specified";
  my $path = get_env_path ($perl_version);

  if (not $args->{info} and @$modules == 1 and ref $modules->[0]) {
    if ($modules->[0]->is_perl) {
      info 1, "cpanm invocation for package |perl| skipped";
      return {};
    }
    my $package = $modules->[0]->package;
    if (defined $package) {
      if ($package eq 'Net::SSLeay' or
          $package eq 'Crypt::SSLeay' or
          $package =~ /^Crypt::OpenSSL::/) {
        info 1, "Net::SSLeay requires OpenSSL (or equivalent)";
        install_openssl_if_too_old ($perl_version);
      } elsif ($package eq 'Image::Magick') {
        info 1, "Image::Magick requires ImageMagick";
        return build_imagemagick
            ($perl_command, $perl_version, $perl_lib_dir_name,
             module_index_file_name => $args->{module_index_file_name});
      }
    }
  }

  _check_perl_version $perl_command, $perl_version unless $args->{info};
  install_cpanm_wrapper;
  if (not $args->{version} and not $CPANMInvoked++) {
    my $r = cpanm ({%$args, info => 0, scandeps => 0, version => 1}, []);
    info 8, "cpanm version:";
    info 8, $r->{output_text};
  }

  my $archname = $args->{info} ? $Config{archname} : get_perl_archname $perl_command, $perl_version;
  my @additional_path;
  my @additional_option;
  my $retry_with_openssl = 0;

  my $redo = 0;
  COMMAND: {
    my @required_cpanm;
    my @required_force_cpanm;
    my @required_install;
    my @required_install2;
    my @required_system;
    my @required_installable;
    my %required_misc;
    my %diag;

    my $cpanm_lib_dir_name = "$RootDirName/local/perl-$perl_version/cpanm";
    my @perl_option = ("-I$cpanm_lib_dir_name/lib/perl5/$archname",
                       "-I$cpanm_lib_dir_name/lib/perl5");

    $args->{local_option} ||= '-l' if $args->{info};
    my @option = ($args->{local_option} || '-L' => $perl_lib_dir_name,
                  ($args->{skip_satisfied} ? '--skip-satisfied' : ()),
                  qw(--notest --cascade-search),
                  ($args->{scandeps} ? ('--scandeps', '--format=json', '--force') : ()));
    push @option, '--force' if $args->{force};
    push @option, '--info' if $args->{info};
    push @option, '--verbose' if $Verbose > 1 and
        not ($args->{scandeps} or $args->{info});
    push @option, '--version' if $args->{version};

    my @module_arg = map {
      ## Implicit dependencies
      $_ eq 'Email::Handle'
          ? ('Class::Accessor::Fast', $_) :
      $_ eq 'RRDTool::OO'
          ? ('Alien::RRDtool', $_) :
      {'GD::Image' => 'GD'}->{$_} || $_;
    } map {
      ref $_ ? $_->as_cpanm_arg (pmtar_dir_name ()) : $_;
    } @$modules;
    if (grep { not m{/misc/[^/]+\.tar\.gz$} } @module_arg) {
      push @option, '--save-dists' => pmtar_dir_name ();
    }

    my @configure_args;
    if (@module_arg and $module_arg[0] eq 'DBD::mysql' and not $args->{info}) {
      push @configure_args, '--ssl';
    }

    push @option,
        '--mirror' => pmtar_dir_name (),
        map { ('--mirror' => $_) }
            @CPANMirror,
            #qw(http://cpan.mirrors.travis-ci.org/) if $ENV{TRAVIS};
            get_cpan_top_url,
            #http://search.cpan.org/CPAN
            qw(
              https://cpan.metacpan.org/
              https://backpan.perl.org/
            );

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

    ## Don't rely on LWP
    push @option, '--no-lwp';

    info 8, sprintf "Current perl version = %vd, target perl version = %s",
        $^V, $perl_version;

    my $cpath = join ':',
        (defined $ENV{CPATH} ? $ENV{CPATH} : ()),
        "$RootDirName/local/common/include";

    my $envs = {LANG => 'C',
                PATH => (join ':', @additional_path, $path),
                PERL5LIB => (join ':', grep { defined and length } 
                                 "$cpanm_lib_dir_name/lib/perl5/$archname",
                                 "$cpanm_lib_dir_name/lib/perl5",
                                 ((sprintf "%vd", $^V) eq $perl_version ? ($ENV{PERL5LIB}) : ())),
                HOME => get_cpanm_dummy_home_dir_name ($perl_lib_dir_name),
                CPATH => $cpath,
                PERL_CPANM_HOME => $CPANMHomeDirName,
                MAKEFLAGS => ''};

    if (-x "$RootDirName/local/common/bin/openssl") {
      $envs->{OPENSSL_PREFIX} = "$RootDirName/local/common";

      ## For Crypt::SSLeay's Makefile.PL
      $envs->{OPENSSL_INCLUDE} = "$RootDirName/local/common/include";
      $envs->{OPENSSL_LIB} = "$RootDirName/local/common/lib";

      if ($retry_with_openssl) {
        ## For DBD::mysql
        $envs->{LIBRARY_PATH} = "$RootDirName/local/common/lib";
      }
    }
     
    if (@module_arg and $module_arg[0] eq 'Crypt::OpenSSL::Random' and
        not $args->{info}) {
      push @configure_args, "LIBDIR=" . "$RootDirName/local/common/lib";
    } elsif (@module_arg and $module_arg[0] eq 'Crypt::OpenSSL::RSA' and
             not $args->{info}) {
      push @option, "--build-args=OTHERLDFLAGS=-L" . "$RootDirName/local/common/lib";
    } elsif (@module_arg and $module_arg[0] eq 'GD' and
        not $args->{info} and not $args->{scandeps}) {
      ## <https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=636649>
      install_makeinstaller 'gd', [q{CCFLAGS="$PMBP__CCFLAGS"}],
          module_build => 1;
      ## Though it has both Makefile.PL and Build.PL, Makefile.PL does
      ## not make GD.so in some Debian environment.
      my $ccflags = '-Wformat=0 ' . get_perl_config $perl_command, $perl_version, 'ccflags';
      $envs->{PMBP__CCFLAGS} = $ccflags;
      $envs->{SHELL} = "$MakeInstaller.gd";
      push @option, '--look';
    } elsif (not $args->{info} and not $args->{scandeps} and
             @$modules and
             defined $modules->[0]->distvname and
             $modules->[0]->distvname =~ /^mod_perl-2\./) {
      install_apache_httpd ('2.2');
      ## <https://perl.apache.org/docs/2.0/user/install/install.html#Dynamic_mod_perl>
      install_makeinstaller 'modperl2', [
        qq{MP_APXS="$RootDirName/local/apache/httpd-2.2/bin/apxs"},
        qq{MP_APR_CONFIG="$RootDirName/local/apache/httpd-2.2/bin/apr-1-config"},
      ];
      $envs->{SHELL} = "$MakeInstaller.modperl2";
      push @option, '--look';
    } elsif (not $args->{info} and not $args->{scandeps} and
             @$modules and
             defined $modules->[0]->distvname and
             $modules->[0]->distvname =~ /^mod_perl-1\./) {
      install_apache1 ();
      ## <https://perl.apache.org/docs/1.0/guide/getwet.html>
      install_makeinstaller 'modperl1', [
        qq{USE_APXS=1},
        qq{WITH_APXS="$RootDirName/local/apache/httpd-1.3/bin/apxs"},
        qq{EVERYTHING=1},
      ];
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
             not $args->{info}) {
      my $mecab_config = mecab_config_file_name ();
      unless (defined $mecab_config) {
        install_mecab ()
            or info_die "Can't install mecab";
        $mecab_config = mecab_config_file_name ();
      }
      # <http://cpansearch.perl.org/src/DMAKI/Text-MeCab-0.20014/tools/probe_mecab.pl>
      my @config = (
        qq{--mecab-config="$mecab_config"},
        qq{--encoding="} . mecab_charset () . q{"},
      );
      unless ($args->{scandeps}) {
        install_makeinstaller 'textmecab', \@config,
            ## Perl 5.26 incompatibly changes "do"'s file lookup rule,
            ## which breaks Text::MeCab's Makefile.PL.
            perl_options => q{-I.};
        $envs->{SHELL} = "$MakeInstaller.textmecab";
        push @option, '--look';
      } else {
        push @configure_args, @config;
      }
      $envs->{LD_LIBRARY_PATH} = mecab_lib_dir_name ();
    } elsif (@module_arg and $module_arg[0] eq 'Math::Pari' and
             not $args->{info} and not $args->{scandeps}) {
      my $file_name = pmtar_dir_name () . '/pari.tar.gz';
      my $PariSourceURL = q<ftp://megrez.math.u-bordeaux.fr/pub/pari/unix/OLD/2.1/pari-2.1.7.tgz>;
      #q<ftp://megrez.math.u-bordeaux.fr/pub/pari/unix/pari.tgz> ## Can't compile with this newer version...
      save_url $PariSourceURL => $file_name
          if not -f $file_name or [stat $file_name]->[9] + 24 * 60 * 60 < time;

      my $pari_version;
      run_command
          ['sh', '-c', 'tar -tz < ' . $file_name],
          onoutput => sub {
            if ($_[0] =~ /^pari-([0-9.]+)/) {
              $pari_version = $1;
            }
            return 20;
          };
      info_die "Can't get pari version from |$file_name|"
          unless defined $pari_version;

      make_path "$PMBPDirName/tmp";
      my $temp_file_name = "$PMBPDirName/tmp/pari-$pari_version.tar.gz";
      run_command ['ln', '-s', $file_name => $temp_file_name];
      info_die "Can't create symlink |$temp_file_name|"
          unless -f $temp_file_name;

      install_makeinstaller 'mathpari', [qq{pari_tgz="$temp_file_name"}];
      $envs->{SHELL} = "$MakeInstaller.mathpari";
      push @option, '--look';
    }
    if (@configure_args) {
      push @option, '--configure-args=' . join ' ', @configure_args;
    }

    ## --- Error message sniffer ---
    my $failed;
    my $remove_inc;
    my $install_extutils_embed;
    my $cpanm_pid;
    my $scan_errors; $scan_errors = sub ($$) {
      my ($level, $log) = @_;
      if ($log =~ /Can\'t locate (\S+\.pm) in \@INC/m) {
        my $mod = PMBP::Module->new_from_pm_file_name ($1);
        if (defined $mod->package and $mod->package eq 'ExtUtils::Embed') {
          $install_extutils_embed = 1;
          $failed = 1;
        } elsif (defined $mod->package and $mod->package eq 'ExtUtils::Manifest') {
          push @required_system, {name => 'perl-ExtUtils-Manifest'}; # core 5.001+
          $failed = 1;
        } elsif ($level <= 2) {
          push @required_cpanm, $mod;
          push @required_install, $mod;
        } else {
          push @required_install, $mod;
        }
      }
      if ($log =~ /^Building version-\S+ \.\.\. FAIL/m) {
        push @required_install,
            map { PMBP::Module->new_from_package ($_) }
            qw{ExtUtils::MakeMaker ExtUtils::ParseXS};
      }
      if ($log =~ /Can't locate object method "new" via package "ExtUtils::ParseXS" at /m) {
        ## Requires 3.18_02 or later
        push @required_install,
            PMBP::Module->new_from_package ('ExtUtils::ParseXS~3.21');
        $failed = 1;
      }
      if ($log =~ /^skipping .+\/perl-/m) {
        if (@module_arg and $module_arg[0] eq 'Module::Metadata') {
          push @required_install, PMBP::Module->new_from_module_arg
              ('Module::Metadata='.get_cpan_top_url.'/authors/id/A/AP/APEIRON/Module-Metadata-1.000011.tar.gz');
          $failed = 1;
        }
      }
      if ($level == 1 and
          ($log =~ /! (?:Installing|Configuring) (\S+) failed\. See (.+?) for details\./m or
           $log =~ /! Configure failed for (\S+)\. See (.+?) for details\.$/m)) {
        my $log = copy_log_file $2 => $1;
        $scan_errors->($level + 1, $log);
        if ($log =~ m{! You might have to install the following modules first to get --scandeps working correctly.\n!((?:\n! \* \S+)+)}) {
          my $modules = $1;
          while ($modules =~ /^! \* (\S+)/mg) {
            push @required_install, PMBP::Module->new_from_package ($1);
          }
        }

        $failed = 1;
      }
      if ($level == 1 and
          $log =~ /! Can't configure the distribution. You probably need to have 'make'. See (.+?) for details./m) {
        my $log = copy_log_file $1 => 'cpanm';
        $scan_errors->($level + 1, $log);
      }
      if ($log =~ m{^(\S+) \S+ is required to configure this module; please install it or upgrade your CPAN/CPANPLUS shell.}m) {
        push @required_install, PMBP::Module->new_from_package ($1);
        # Don't set $failed flag.
      }
      if ($log =~ m{^ERROR from evaluation of .+/vutil/Makefile.PL: ExtUtils::MM_Unix::tool_xsubpp : Can't find xsubpp at }m) {
        push @required_cpanm,
            map { PMBP::Module->new_from_package ($_) }
            qw{ExtUtils::MakeMaker ExtUtils::ParseXS};
        $failed = 1;
      }
      if ($log =~ m{error: perl.h: No such file or directory}m) {
        push @required_system,
            {name => 'perl-devel',
             redhat_name => 'perl-libs',
             debian_name => 'libperl-dev'};
      }
      if ($log =~ m{^make(?:\[[0-9]+\])?: .+?ExtUtils/xsubpp}m or
          $log =~ m{^Can\'t open perl script ".*?ExtUtils/xsubpp"}m) {
        push @required_install,
            map { PMBP::Module->new_from_package ($_) }
            qw{ExtUtils::MakeMaker ExtUtils::ParseXS};
        $failed = 1;
      }
      if ($log =~ m{Undefined subroutine &ExtUtils::ParseXS::\S+ called}m) {
        push @required_install,
            map { PMBP::Module->new_from_package ($_) }
            qw{ExtUtils::MakeMaker ExtUtils::ParseXS};
        $failed = 1;
      }
      if ($log =~ /^MoreUtils.xs:.+?: error: 'GIMME' undeclared/m) {
        push @required_install, PMBP::Module->new_from_package ('List::MoreUtils~0.410');
      }
      if ($log =~ /Failed to extract .+?.tar.gz - You need to have tar or Archive::Tar installed./m) {
        #push @required_cpanm, PMBP::Module->new_from_package ('Archive::Tar'); # core 5.9.3+
        push @required_installable, 'tar';
      }
      if ($log =~ /Failed to extract .+.zip - You need to have unzip or Archive::Zip installed./m) {
        push @required_cpanm, PMBP::Module->new_from_package ('Archive::Zip');
      }
      if ($log =~ /^(JSON::PP) ([0-9.]+) is not available/m) {
        push @required_cpanm, PMBP::Module->new_from_package ($1 . '~' . $2);
      }
      if ($log =~ /^only nested arrays of non-refs are supported at .*?\/ExtUtils\/MakeMaker.pm/m) {
        push @required_install,
            PMBP::Module->new_from_package ('ExtUtils::MakeMaker');
      }
      if ($log =~ /^\s*\+ Module::Install$/m) {
        push @required_install, PMBP::Module->new_from_package ('Module::Install');
      }
      if ($log =~ /^String found where operator expected at Makefile.PL line [0-9]+, near \"([0-9A-Za-z_]+)/m) {
        my $module_name = {
          author_tests => 'Module::Install::AuthorTests',
          readme_from => 'Module::Install::ReadmeFromPod',
          readme_markdown_from => 'Module::Install::ReadmeMarkdownFromPod',
        }->{$1};
        push @required_install, PMBP::Module->new_from_package ($module_name)
            if $module_name;
      }
      if ($log =~ /^Bareword "([0-9A-Za-z_]+)" not allowed while "strict subs" in use at Makefile.PL /m) {
        my $module_name = {
          auto_manifest => 'Module::Install::AutoManifest',
          auto_set_repository => 'Module::Install::Repository',
          githubmeta => 'Module::Install::GithubMeta',
          use_test_base => 'Module::Install::TestBase',
        }->{$1};
        push @required_install, PMBP::Module->new_from_package ($module_name)
            if $module_name;
      }
      if ($log =~ m{\Qsyntax error at inc/Module/Install/AutoInstall.pm - /Library/Perl/5.8.1/Module/Install/AutoInstall.pm line 26, near "m/--(?:default|skip|testonly)/and-t "\E}) {
        push @required_install, PMBP::Module->new_from_package ('Module::Install::AutoInstall');
      }
      if ($log =~ m{^(Devel::CheckLib) not found in inc/ nor \@INC at inc/Module/Install/XSUtil.pm}m) {
        push @required_cpanm, PMBP::Module->new_from_package ($1);
      }
      if ($log =~ /Checking if you have Module::Build [0-9.]+ ... No \([0-9.]+ < ([0-9.]+)\)/m) {
        push @required_cpanm, PMBP::Module->new_from_package ('Module::Build~' . $1);
      }
      if ($log =~ /Base class package "(Module::Build::[^"]+)" is empty./m) {
        push @required_cpanm, PMBP::Module->new_from_package ($1);
      }
      if ($log =~ /perl is loading libcrypto in an unsafe way/) {
        ## <https://stackoverflow.com/questions/67003619/mac-m1-homebrew-perl-carton-netssleay-is-loading-libcrypto-in-an-unsafe-way>
        push @required_install, PMBP::Module->new_from_package
            ('ExtUtils::MakeMaker~7.58');
      }
      if ($log =~ /and Net::SSLeay\. Mixing and matching compilers is not supported\./) {
        #"*** Be sure to use the same compiler and options to compile your OpenSSL, perl,"
        #"    and Net::SSLeay. Mixing and matching compilers is not supported."
        $required_misc{openssl} = 1 if $redo > 1;
      }
      if ($log =~ m{Module::CoreList \S+ \(loaded from .*\) doesn't seem to have entries for perl \S+. You're strongly recommended to upgrade Module::CoreList from CPAN.}m) {
        push @required_force_cpanm, PMBP::Module->new_from_package ('Module::CoreList');
      }
      if ($log =~ /^Can\'t call method "load_all_extensions" on an undefined value at inc\/Module\/Install.pm /m) {
        $remove_inc = 1;
      }
      if ($log =~ m{Invalid version format \(version required\) at .+/Module/Runtime.pm line }m) {
        ## Moose version inconsistency
        push @required_install, PMBP::Module->new_from_package ('Moose');
      }
      if ($log =~ /^(\S+) version \S+ required--this is only version \S+/m) {
        push @required_install, PMBP::Module->new_from_package ($1);
      }
      if ($log =~ m{^One can rerun Makefile.PL after fetching GP/PARI archive}m and
          not (@module_arg and $module_arg[0] eq 'Math::Pari')) {
        push @required_install, PMBP::Module->new_from_package ('Math::Pari');
      }
      if ($log =~ /^cc: Internal error: Killed \(program cc1\)/m and
          @module_arg and $module_arg[0] eq 'Net::SSLeay') {
        ## In some environment latest version of Net::SSLeay fails to
        ## compile.  According to Google-sensei |nice| could resolve
        ## the problem but I can't confirm it.  Downgrading to 1.36 or
        ## earlier and installing outside of cpanm succeeded (so some
        ## environment variable set by cpanm affects the building
        ## process?).  (Therefore the line below is incomplete, but I
        ## can no longer reproduce the problem.)
        push @required_install, PMBP::Module->new_from_module_arg
            ('Net::SSLeay~1.36='.get_cpan_top_url.'/authors/id/F/FL/FLORA/Net-SSLeay-1.36.tar.gz');
      }
      if ($log =~ m{^lib/Params/Validate/XS.xs:.+?: error: .*?cvgv.*? undeclared \(first use in this function\)}m) {
        ## Downgrade Params::Validate 1.12 -> 1.11
        push @required_install, PMBP::Module->new_from_module_arg
            ('Params::Validate~1.11='.get_cpan_top_url.'/authors/id/D/DR/DROLSKY/Params-Validate-1.11.tar.gz');
        push @additional_option, '--skip-satisfied';
      }
      if ($log =~ /Can't configure the distribution. You probably need to have 'make'/m) {
        push @required_installable, 'make';
      }
      if ($log =~ /cannot find -lz/m) {
        push @required_system,
            {name => 'zlib-devel', debian_name => 'zlib1g-dev'};
      }
      if ($log =~ m{error: openssl/\w+.h: No such file or directory}m or
          $log =~ m{error: 'openssl/\w+.h' file not found}m or
          (not $args->{info} and not $args->{scandeps} and
           @module_arg and $module_arg[0] =~ /^Crypt::OpenSSL::/ and
           $log =~ m{.+\.xs:.+?error: })) {
        $required_misc{openssl} = 1;
        #push @required_system,
        #    {name => 'openssl-devel', debian_name => 'libssl-dev',
        #     homebrew_name => 'openssl'};
        $failed = 1;
      }
      if ($log =~ m{ld: library not found for -lssl}m) {
        $required_misc{openssl_ld} = 1;
      }
      if ($log =~ m{^Can't link/include (?:C library )?'gmp.h', 'gmp'}m) {
        push @required_system,
            {name => 'gmp-devel', debian_name => 'libgmp-dev',
             homebrew_name => 'gmp'};
        $failed = 1;
      }
      if ($log =~ m{^Can't link/include 'v8'}m) {
        push @required_system, {name => 'v8-devel', debian_name => 'libv8-dev',
                                homebrew_name => 'v8'};
      }
      if ($log =~ /^Could not find gdlib-config in the search path. Please install libgd /m or
          $log =~ /^No package 'gdlib' found/m) {
        push @required_system,
            {name => 'gd-devel', debian_name => 'libgd2-xpm-dev',
             homebrew_name => 'gd'};
        $failed = 1;
      }
      if ($log =~ /fatal error: mpfr.h: No such file or directory/m) {
        push @required_system,
            {name => 'mpfr-devel', debian_name => 'libmpfr-dev'};
        $failed = 1;
      }
      if ($log =~ m{ld: cannot find -lmysqlclient}m) {
        push @required_installable, 'mysqld';
        $failed = 1;
      }
      if ($log =~ /^The value of POSTGRES_INCLUDE points to a non-existent directory/m or
          $log =~ /^You need to install postgresql-server-dev-X.Y for building a server-side extension or libpq-dev for building a client-side application./m or
          $log =~ /No POSTGRES_HOME defined, cannot find automatically/m) {
        push @required_system, {name => 'postgresql-devel',
                                debian_name => 'libpq-dev',
                                homebrew_name => 'postgresql'};
      }
      if ($log =~ m{ld: cannot find -lperl}m) {
        push @required_system,
            {name => 'perl-devel',
             redhat_name => 'perl-libs',
             debian_name => 'libperl-dev'};
      }
      if ($log =~ m{Can't exec "mysql_config": No such file or directory}m) {
        push @required_system,
            {name => 'mysql-client-devel',
             #redhat_name => 'MySQL-devel',
             redhat_name => 'mariadb-devel',
             #debian_name => 'libmysqlclient-dev',
             debian_name => 'libmariadbclient-dev',
             homebrew_name => 'mysql'};
        $failed = 1;
      }
      if ($log =~ m{Can't link/include C library 'ssl', 'crypto', aborting.}) {
        # DBD::mysql
        $required_misc{openssl_ld} = 1;
      }
      if ($log =~ /^version.c:.+?: (?:fatal |)error: db.h: No such file or directory/m and
          $log =~ /^-> FAIL Installing DB_File failed/m) {
        push @required_system,
            {name => 'bdb-devel', redhat_name => 'db-devel',
             debian_name => 'libdb-dev'};
        $failed = 1;
      }
      if ($log =~ m{ld: cannot find -lperl$}m) {
        push @required_system,
            {name => 'perl-devel',
             redhat_name => 'perl-libs',
             debian_name => 'libperl-dev'};
        $failed = 1;
      }
      if ($log =~ /^Expat.xs:.+?: error: expat.h: No such file or directory/m) {
        push @required_system,
            {name => 'expat-devel', debian_name => 'libexpat1-dev'};
        $failed = 1;
      }
      if ($log =~ /to see the exact reason why the detection of libxml2 installation/m) {
        push @required_system,
            {name => 'libxml2-devel', debian_name => 'libxml2-dev'};
        $failed = 1;
      }
      if ($log =~ /^This module requires GNU Libidn, which could not be found./m) {
        push @required_system,
            {name => 'libidn-devel', debian_name => 'libidn11-dev'};
        $failed = 1;
      }
      if ($log =~ /fatal error: libkakasi.h: No such file or directory/m or
          $log =~ /fatal error: 'libkakasi.h' file not found/m) {
        push @required_system,
            {name => 'kakasi-devel', debian_name => 'libkakasi2-dev',
             homebrew_name => 'kakasi'};
        $failed = 1;
      }
      if ($log =~ /error: Your compiler is not powerful enough to compile MeCab/m) {
        push @required_system, {name => 'build-essential'}; # debian
        $failed = 1;
      }
      if ($log =~ /^Can\'t proceed without mecab-config./m) {
        $required_misc{mecab} = 1;
        $failed = 1;
      }
      if ($log =~ /^The GeoIP CAPI is not installed you should do that. Otherwise try/m) {
        push @required_system,
            {name => 'GeoIP-devel', debian_name => 'libgeoip-dev'};
        $failed = 1;
      }
      if ($log =~ /^ERROR: proj library not found, where is cs2cs\?/m) {
        push @required_system,
            {name => 'proj-devel', debian_name => 'libproj-dev'};
        $failed = 1;
      }
      if ($log =~ /^\*\*\* ExtUtils::PkgConfig requires the pkg-config utility, but it doesn't/m) {
        push @required_system,
            {name => 'pkg-config', redhat_name => 'pkgconfig'};
      }
      if ($log =~ /^\* I could not find a working copy of (\S+)\./m) {
        my $name = $1;
        if ($name eq 'glib-2.0') {
          push @required_system,
              {name => 'glib2-devel', debian_name => 'libglib2.0-dev'};
        } elsif ($name eq 'pangocairo') {
          push @required_system,
              {name => 'pango-devel', debian_name => 'libpango1.0-dev',
               homebrew_name => 'pango'};
        } elsif ($name =~ /^cairo-/) {
          # cairo-png cairo-ps cairo-pdf cairo-svg
          push @required_system,
              {name => 'cairo-devel', debian_name => 'libcairo-dev'};
        } else {
          push @required_system, {name => $name};
        }
      }
      if ($log =~ /^! Couldn\'t find module or a distribution (\S+) \(/m) {
        my $mod = {
          'Date::Parse' => 'Date::Parse',
          'Test::Builder::Tester' => 'Test::Simple', # Test-Simple 0.98 < TBT 1.07
        }->{$1};
        push @required_install,
            PMBP::Module->new_from_package ($mod) if $mod;
      }
      if ($log =~ /^Could not find Python.h in include path. make will not work at Makefile.PL/m) {
        push @required_system,
            {name => 'python-devel', debian_name => 'python-dev'};
      }
      if ($log =~ /\bsh: 1: cc: not found$/m or
          $log =~ /\bsh: gcc: command not found/m or
          $log =~ /^configure: error: no acceptable C compiler found/m) {
        push @required_installable, 'gcc';
      }
      if ($log =~ /^# This module requires vim version 6.0 or later/m) {
        push @required_installable, 'vim';
        $failed = 1;
      }
      if ($log =~ /^We have to reconfigure CPAN.pm due to following uninitialized parameters:/m) {
        kill 15, $cpanm_pid;
        push @required_cpanm, PMBP::Module->new_from_package ('CPAN');
        $required_misc{cpan} = 1;
        $failed = 1;
      }
      if ($log =~ /^Undefined subroutine &Scalar::Util::blessed called/m) {
        if ($ENV{PERL5LIB} or $ENV{PERL5OPT}) {
          $diag{env} = 1;
        }
      }
      if ($log =~ /^! Can't configure the distribution\. You probably need to have 'make'\./m) {
        push @required_installable, 'make';
      }
      if ($log =~ /^!!! MakeInstaller failed !!!$/m) {
        $failed = 1;
      }
      if ($log =~ m{/cpanm did not return a true value at }m) {
        unlink $CPANMCommand;
        install_cpanm;
        $failed = 1;
      }
      if ($log =~ m{^Perl v([0-9.]+) required--this is only v([0-9.]+), stopped at }m) {
        info 0, "Perl $1 or later is requested (current: $2)";
        $failed = 1;
      }
      if (not $failed and
          $log =~ m{-> FAIL Installing (Crypt::OpenSSL::Random|Crypt::OpenSSL::RSA|GD|Text::MeCab|Math::Pari) failed. See} and
          not (@module_arg and $module_arg[0] eq $1 and
               not $args->{info})) {
        push @required_install,
            PMBP::Module->new_from_package ($1);
      }
    }; # $scan_errors
    ## --- End of error message sniffer ---

    my @cmd = ($perl_command,
               @perl_option,
               $CPANMWrapper,
               @option,
               @additional_option,
               @module_arg);
    my $json_temp_file_name;
    my $cpanm_error = '';
    my $cpanm_ok = run_command \@cmd,
        envs => $envs,
        info_command_level => $args->{info} ? 2 : 1,
        profiler_name => ($args->{scandeps} ? 'cpanm-scandeps' : $args->{info} ? 'cpanm-info' : 'cpanm'),
        prefix => "cpanm($CPANMDepth/$redo): ",
        '>' => (($args->{scandeps} || $args->{info} || $args->{version}) ? do {
          $json_temp_file_name = create_temp_file_name;
        } : undef),
        discard_stderr => (($args->{scandeps} || $args->{info}) ? 1 : 0),
        '$$' => \$cpanm_pid,
        '$?' => \$cpanm_error,
        onoutput => sub {
          my $info_level = 1;
          if ($_[0] =~ /^! Couldn\'t find module or a distribution /) {
            $info_level = 0;
          }
          $scan_errors->(1, $_);
          return $info_level;
        },
        onstderr => sub {
          $scan_errors->(1, $_);
          return 1;
        };
    info 2, "cpanm done (exit status @{[$cpanm_error >> 8]})";
    if (not $cpanm_ok and not $failed and (($cpanm_error >> 8) == 1) and
        $args->{scandeps} and -f $json_temp_file_name) {
      ## cpanm --scandeps exits with return value 1...
      $cpanm_ok = 1;
    }

    if (defined $json_temp_file_name and -f $json_temp_file_name) {
      info_log_file 3, $json_temp_file_name => 'cpanm STDOUT';
    }
    if ($args->{info} and
        defined $json_temp_file_name and -f $json_temp_file_name) {
      ## Example output:
      ## ==> Found dependencies: ExtUtils::MakeMaker, ExtUtils::Install
      ## BINGOS/ExtUtils-MakeMaker-6.72.tar.gz
      ## YVES/ExtUtils-Install-1.54.tar.gz
      ## FAYLAND/WWW-Contact-0.47.tar.gz
      open my $file, '<', $json_temp_file_name or info_die "$0: $!";
      local $/ = undef;
      $result->{output_text} = [grep { length } split /\x0D?\x0A/, <$file>]->[-1];
    } elsif ($args->{scandeps} and
             defined $json_temp_file_name and -f $json_temp_file_name) {
      ## Parse JSON data, ignoring any progress before it...
      my $garbage;
      ($garbage, $result->{output_json}) = load_json_after_garbage $json_temp_file_name;
      unless (@{$result->{output_json} or []}) {
        unless ($redo++ > 10) {
          info 1, "Retrying cpanm --scandeps...";
          redo COMMAND;
        }
        $failed = "no output json data";
      }
      $scan_errors->(1, $garbage);
    } elsif ($args->{version} and
             defined $json_temp_file_name and -f $json_temp_file_name) {
      open my $file, '<', $json_temp_file_name or info_die "$0: $!";
      local $/ = undef;
      $result->{output_text} = <$file>;
    }

    unless ($cpanm_ok and not $failed) {
      unless ($CPANMDepth > 100 or $redo++ > 10) {
        my $redo;
        if ($remove_inc and
            @module_arg and $module_arg[0] =~ m{/} and
            -d "$module_arg[0]/inc") {
          remove_tree "$module_arg[0]/inc";
          $redo = 1;
        }
        if (@required_installable) {
          install_commands \@required_installable;
          $redo = 1;
        }
        if (@required_system) {
          $redo = 1 if install_system_packages \@required_system;
        }
        for (keys %required_misc) {
          info 6, "Sniffed required misc dependency: |$_|";
        }
        if ($required_misc{openssl}) {
          $retry_with_openssl = 1;
          $redo = 1 if install_openssl ($perl_version);
        }
        if ($required_misc{openssl_ld}) {
          $retry_with_openssl = 1;
          if ($PlatformIsMacOSX) {
            $redo = 1 if xcode_select_install or install_openssl ($perl_version);
          } else {
            $redo = 1 if install_openssl ($perl_version);
          }
        }
        if ($required_misc{mecab}) {
          $redo = 1 if install_mecab ();
        }
        if ($install_extutils_embed) {
          ## ExtUtils::Embed is core module since 5.003_07 and you
          ## should have the module installed.  Newer versions of the
          ## module is not distributed at CPAN.  Nevertheless, on some
          ## system the module is not installed...
          my $pm = "$perl_lib_dir_name/lib/perl5/ExtUtils/Embed.pm";
          save_url q<https://raw.githubusercontent.com/Perl/perl5/blead/lib/ExtUtils/Embed.pm> => $pm;
          undef $install_extutils_embed;
          $redo = 1;
        }
        if (not @required_system and not @required_installable and
            (@required_cpanm or @required_force_cpanm)) {
          ## |@required_cpanm| - CPAN Perl modules need to be
          ## installed for running |cpanm|.
          local $CPANMDepth = $CPANMDepth + 1;
          for my $module (@required_cpanm) {
            if ($module->package eq 'Test::Harness') {
              my $file_name = "$cpanm_lib_dir_name/lib/perl5/Test/Harness.pm";
              mkdir_for_file $file_name;
              open my $file, '>', $file_name;
              print $file "1;";
              close $file;
            } elsif ($module->package eq 'ExtUtils::Manifest') {
              my $file_name = "$cpanm_lib_dir_name/lib/perl5/ExtUtils/Manifest.pm";
              save_url q<https://raw.githubusercontent.com/rafl/extutils-manifest/master/lib/ExtUtils/Manifest.pm> => $file_name;
              save_url q<https://fastapi.metacpan.org/source/JPEACOCK/version-0.9908/lib/version.pm> => "$cpanm_lib_dir_name/lib/perl5/version.pm";
              save_url q<https://fastapi.metacpan.org/source/JPEACOCK/version-0.9908/lib/version/regex.pm> => "$cpanm_lib_dir_name/lib/perl5/version/regex.pm";
              next;
            }
            get_local_copy_if_necessary ($module);
            cpanm {perl_command => $perl_command,
                   perl_version => $perl_version,
                   perl_lib_dir_name => $cpanm_lib_dir_name,
                   local_option => '-l', skip_satisfied => 1}, [$module];
          }
          for my $module (@required_force_cpanm) {
            get_local_copy_if_necessary ($module);
            cpanm {perl_command => $perl_command,
                   perl_version => $perl_version,
                   perl_lib_dir_name => $cpanm_lib_dir_name,
                   local_option => '-l', skip_satisfied => 0}, [$module];
          }
          $redo = 1;
        } elsif (@required_install) {
          ## |@required_install| - CPAN Perl modules need to be
          ## installed for running the application or build scripts of
          ## modules.
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
        if ($required_misc{cpan}) {
          if (install_cpan_config $perl_command, $perl_version, $perl_lib_dir_name) {
            $redo = 1;
          }
        }
        if (not $redo) {
          my $cc = get_perl_config $perl_command, $perl_version, 'cc';
          unless (which $cc) {
            info 1, 'There is no gcc; Installing gcc before retrying...';
            ## There is the platform's perl binary, but there is no compiler.
            $redo = 1 if install_system_packages [{name => 'gcc'}];
          } else {
            info 0, "Can't detect why cpanm failed";
          }
        }
        redo COMMAND if $redo;
      }
      if ($args->{info}) {
        #
      } elsif ($args->{ignore_errors}) {
        info 0, "cpanm($CPANMDepth): Processing @{[join ' ', map { ref $_ ? $_->as_short : $_ } @$modules]} failed (@{[$? >> 8]}) (Ignored)";
      } else {
        if ($diag{env}) {
          info 0, "Environment variables |PERL5LIB| and/or |PERL5OPT| is set.  Is this really intentional?";
        }
        info_die "cpanm($CPANMDepth): Processing @{[join ' ', map { ref $_ ? $_->as_short : $_ } @$modules]} failed (@{[$? >> 8]}@{[($failed and not $failed eq '1') ? qq< $failed>: '']})\n";
      }
    } # apparently failed

    if (not $args->{info} and not $args->{scandeps} and
        @module_arg and $module_arg[0] eq 'Net::SSLeay') {
      my $result;
      my @lib = get_lib_dir_names_of ($perl_command, $perl_version, $perl_lib_dir_name);
      my $return = run_command
          [$perl_command,
           (map { '-I' . $_ } @lib),
           '-MNet::SSLeay',
           '-e', 'print scalar Net::SSLeay::ST_OK ()'],
          envs => {PATH => get_env_path ($perl_version)},
          info_level => 3,
          onoutput => sub {
            $result = $_[0];
            return 3;
          };
      unless ($result =~ /\A[0-9]+\z/) {
        info 1, "OpenSSL or Net::SSLeay is broken [$result]";
        unless ($CPANMDepth > 100 or $redo++ > 10) {
          install_openssl ($perl_version);
          $args->{force} = 1;
          redo COMMAND;
        } else {
          info_die "OpenSSL or Net::SSLeay is broken ($CPANMDepth/$redo)";
        }
      }
    }

    if (@module_arg and $module_arg[0] eq 'CPAN' and
        not $args->{info} and not $args->{scandeps}) {
      install_cpan_config $perl_command, $perl_version, $perl_lib_dir_name;
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
      [stat $file_name]->[9] + 24 * 60 * 60 < time or # mtime
      [stat $file_name]->[7] < 1 * 1024 * 1024) {
    save_url get_cpan_top_url . q<modules/02packages.details.txt.gz>
        => $file_name;
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
  my $cpan_top_url = get_cpan_top_url;
  my $index =  PMBP::ModuleIndex->new_from_arrayref ([
    ## Stupid workaround for cpanm's broken version comparison
    PMBP::Module->new_from_module_arg ('ExtUtils::MakeMaker~6.6302='.get_cpan_top_url.'/authors/id/M/MS/MSCHWERN/ExtUtils-MakeMaker-6.63_02.tar.gz'),

    PMBP::Module->new_from_module_arg ('IDNA::Punycode~0.03='.get_cpan_top_url.'/authors/id/R/RO/ROBURBAN/IDNA-Punycode-0.03.tar.gz'),
    PMBP::Module->new_from_module_arg ('WWW::Contact~0.47='.get_cpan_top_url.'/authors/id/F/FA/FAYLAND/WWW-Contact-0.47.tar.gz'),
    PMBP::Module->new_from_module_arg ('RRDs='.get_cpan_top_url.'/authors/id/G/GF/GFUJI/Alien-RRDtool-0.05.tar.gz'),
    PMBP::Module->new_from_module_arg ('RRDp='.get_cpan_top_url.'/authors/id/G/GF/GFUJI/Alien-RRDtool-0.05.tar.gz'),

    ## Obsolete
    PMBP::Module->new_from_module_arg ('Email::Handle~0.01=http://backpan.perl.org/authors/id/N/NA/NAOYA/Email-Handle-0.01.tar.gz'),
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

  for (
    #qw(http://cpan.mirrors.travis-ci.org/) if $ENV{TRAVIS};
    main::get_cpan_top_url,
    #http://search.cpan.org/CPAN
    @CPANMirror,
    qw(
      https://cpan.metacpan.org/
      https://backpan.perl.org/
    ),
  ) {
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
        copy_file $mirror => $dest_file_name or
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
        if ($PlatformIsWindows) {
          run_command
              ['mkdir', $PMTarDirName],
              chdir => $RootDirName;
          run_command
              ['dir', $PMTarDirName],
              chdir => $RootDirName,
              info_level => 10
              or info_die "Can't create $PMTarDirName at $RootDirName";
        } else {
          run_command
              ['mkdir', '-p', $PMTarDirName],
              chdir => $RootDirName
              or info_die "Can't create $PMTarDirName at $RootDirName";
        }
        run_command
            ['sh', '-c', "cd \Q$PMTarDirName\E && pwd"],
            chdir => $RootDirName,
            discard_stderr => 1,
            onoutput => sub { $PMTarDirName = $_[0]; 4 }
            or info_die "Can't get pmtar directory name";
        $PMTarDirName =~ s/[\x0D\x0A]+\z//;
      }
      $pmtar_dir_created = 1;
    }
    return $PMTarDirName;
  } # pmtar_dir_name

  my $pmpp_dir_created;
  sub pmpp_dir_name () {
    unless ($pmpp_dir_created) {
      if ($PlatformIsWindows) {
        run_command
            ['mkdir', $PMPPDirName],
            chdir => $RootDirName;
        run_command
            ['dir', $PMPPDirName],
            chdir => $RootDirName,
            info_level => 10
            or info_die "Can't create $PMPPDirName at $RootDirName";
      } else {
        run_command
            ['mkdir', '-p', $PMPPDirName],
            chdir => $RootDirName
            or info_die "Can't create $PMPPDirName at $RootDirName";
      }
      run_command
          ['sh', '-c', "cd \Q$PMPPDirName\E && pwd"],
          chdir => $RootDirName,
          discard_stderr => 1,
          onoutput => sub { $PMPPDirName = $_[0]; 4 }
          or info_die "Can't get pmpp directory name";
      $PMPPDirName =~ s/[\x0D\x0A]+\z//;
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
  run_command [git, 'init'],
      chdir => pmtar_dir_name;
} # init_pmtar_git

sub init_pmpp_git () {
  return if -f (pmpp_dir_name . "/.git/config");
  run_command [git, 'init'],
      chdir => pmpp_dir_name;
} # init_pmpp_git

sub git_pull_current_or_master ($) {
  my $git_dir_name = shift;
  return 0 unless -f "$git_dir_name/.git/config";
  my $branch = '';
  run_command [git, 'branch'],
      chdir => $git_dir_name,
      discard_stderr => 1,
      onoutput => sub { $branch .= $_[0]; 5 };
  if ($branch =~ /^\* \(no branch\)$/m) {
    run_command
        [git, 'checkout', 'master'],
        chdir => $git_dir_name
            or return 0;
  }
  return run_command [git, 'pull'], chdir => $git_dir_name;
} # git_pull_current_or_master

sub pmtar_git_pull () {
  git_pull_current_or_master pmtar_dir_name;
} # pmtar_git_pull

sub pmpp_git_pull () {
  git_pull_current_or_master pmpp_dir_name;
} # pmpp_git_pull

sub rewrite_perl_shebang ($$$) {
  my ($old_file_name => $new_file_name, $perl_path) = @_;
  local $/ = undef;
  open my $old_file, '<', $old_file_name
      or info_die "$0: $old_file_name: $!";
  my $content = <$old_file>;
  if (($perl_path =~ /env perl/ and $content =~ s{^#!.*?perl.*$}{#!$perl_path}m) or ## |env| does not support multiple args
      $content =~ s{^#!.*?perl[0-9.]*(?:$|(?=\s))}{#!$perl_path}m or
      not $old_file_name eq $new_file_name) {
    open my $new_file, '>', $new_file_name
        or info_die "$0: $new_file_name: $!";
    binmode $new_file;
    print $new_file $content;
    close $new_file;
  }
} # rewrite_perl_shebang

sub copy_pmpp_modules ($$) {
  my ($perl_command, $perl_version) = @_;
  return unless run_command ['sh', '-c', "cd \Q$PMPPDirName\E"];
  hide_pmpp_arch_dir ($perl_command, $perl_version);

  my $ignores = [map { s{^/}{}; s{/$}{}; $_ } grep { 
    m{^/.+/$};
  } @{read_gitignore (pmpp_dir_name . "/.gitignore") || []}];

  profiler_start 'file';
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
          rewrite_perl_shebang $_ => $dest, $perl_path;
        } else {
          copy_file $_ => $dest or info_die "$0: $dest: $!";
        }
        chmod ((stat $_)[2], $dest);
      } elsif (-d $_) {
        info 2, "Copying directory $rel...";
        make_path $dest;
        chmod ((stat $_)[2], $dest);
      }
    }, $dir_name);
  }
  profiler_stop 'file';
} # copy_pmpp_modules

sub delete_pmpp_arch_dir ($$) {
  my ($perl_command, $perl_version) = @_;
  my $archname = get_perl_archname $perl_command, $perl_version;
  remove_tree (pmpp_dir_name . "/lib/perl5/$archname/");
} # delete_pmpp_arch_dir

sub hide_pmpp_arch_dir ($$) {
  my ($perl_command, $perl_version) = @_;
  my $archname = get_perl_archname $perl_command, $perl_version;
  add_to_gitignore ["/lib/perl5/$archname/", '/man/']
      => pmpp_dir_name . "/.gitignore";
} # hide_pmpp_arch_dir

## ------ Local Perl module directories ------

sub get_pm_dir_name ($) {
  my $perl_version = shift;
  return "$RootDirName/local/perl-$perl_version/pm";
} # get_pm_dir_name

sub get_lib_dir_names_of ($$$) {
  my ($perl_command, $perl_version, $pm_dir_name) = @_;
  my $archname = get_perl_archname $perl_command, $perl_version;
  return (
    qq{$pm_dir_name/lib/perl5/$archname},
    qq{$pm_dir_name/lib/perl5},
  );
} # get_lib_dir_names_of

sub get_lib_dir_names ($$) {
  my ($perl_command, $perl_version) = @_;
  my $pm_dir_name = get_pm_dir_name ($perl_version);
  my @lib = grep { defined } map { abs_path $_ } map { glob $_ }
      qq{$RootDirName/lib},
      qq{$RootDirName/modules/*/lib},
      qq{$RootDirName/local/submodules/*/lib},
      get_lib_dir_names_of ($perl_command, $perl_version, $pm_dir_name);
  return @lib;
} # get_lib_dir_names

sub get_relative_lib_dir_names ($$) {
  return map {
    File::Spec->abs2rel ($_, $RootDirName) ;
  } get_lib_dir_names ($_[0], $_[1]);
} # get_relative_lib_dir_names

sub get_libs_txt_file_name ($) {
  my $perl_version = shift;
  return "$RootDirName/local/config/perl/libs-$perl_version-$Config{archname}.txt";
} # get_libs_txt_file_name

sub get_relative_libs_txt_file_name ($) {
  my $perl_version = shift;
  return "$RootDirName/local/config/perl/relative-libs-$perl_version-$Config{archname}.txt";
} # get_relative_libs_txt_file_name

sub write_libs_txt ($$$) {
  my ($perl_command, $perl_version => $file_name) = @_;
  mkdir_for_file $file_name;
  open my $file, '>', $file_name or info_die "$0: $file_name: $!";
  info_writing 3, "lib paths", $file_name;
  print $file join ':', (get_lib_dir_names ($perl_command, $perl_version));
} # write_libs_txt

sub write_relative_libs_txt ($$$) {
  my ($perl_command, $perl_version => $file_name) = @_;
  mkdir_for_file $file_name;
  open my $file, '>', $file_name or info_die "$0: $file_name: $!";
  info_writing 3, "relative lib paths", $file_name;
  print $file join ':', (get_relative_lib_dir_names ($perl_command, $perl_version));
} # write_relative_libs_txt

sub rewrite_pm_bin_shebang ($) {
  my $perl_version = shift;
  profiler_start 'file';
  require File::Find;
  my $bin_path = abs_path (get_pm_dir_name ($perl_version) . '/bin');
  return if not defined $bin_path or not -d $bin_path;
  my $env = which 'env';
  File::Find::find (sub {
    if (-f $_) {
      run_command ['chmod', 'u+w', $_];
      rewrite_perl_shebang $_ => $_, "$env perl";
    }
  }, $bin_path);
  profiler_stop 'file';
} # rewrite_pm_bin_shebang

sub get_envs_for_perl ($$) {
  my ($perl_command, $perl_version) = @_;
  return {
    PATH => get_env_path ($perl_version),
    PERL5LIB => (join ':', (get_lib_dir_names ($perl_command, $perl_version))),
  };
} # get_envs_for_perl

sub create_perl_command_shortcut ($$$;%) {
  my ($perl_version, $command => $file_name, %args) = @_;
  $file_name = resolve_path $file_name, $RootDirName;
  my $arg;
  ($command, $arg) = @$command if defined $command and ref $command eq 'ARRAY';
  $command = resolve_path $command, $RootDirName
      if defined $command and $command =~ m{/};
  $arg = resolve_path $arg, $RootDirName if defined $arg and not $args{relocatable};
  mkdir_for_file $file_name;
  info_writing 1, "command shortcut", $file_name;
  my @bin_path;
  push @bin_path, get_perlbrew_perl_bin_dir_name $perl_version;
  push @bin_path, get_pm_dir_name ($perl_version) . "/bin";
  push @bin_path, resolve_path "local/common/bin", $RootDirName;
  push @bin_path, mecab_bin_dir_name ();
  my @lib_path;
  push @lib_path, get_pm_dir_name ($perl_version) . "/lib";
  push @lib_path, resolve_path "local/common/lib", $RootDirName;
  push @lib_path, mecab_lib_dir_name ();
  open my $file, '>', $file_name or info_die "$0: $file_name: $!";
  my $paths;
  if ($args{relocatable}) {
    my $file_path = resolve_path '..', $file_name;
    my $root_path = File::Spec->abs2rel ($RootDirName, $file_path);
    $command = File::Spec->abs2rel ($command, $RootDirName)
        if defined $command and $command =~ m{/};
    for (@bin_path, @lib_path) {
      $_ = File::Spec->abs2rel ($_);
      $_ = '$rootpath/' . $_;
    }
    $paths = sprintf q{
rootpath=$(cd %s && pwd)
libpaths=`cat $rootpath/%s 2> /dev/null | perl -MCwd=abs_path -e '$p = abs_path shift; local $/ = undef; print join q{:}, map { $p . q{/} . $_ } split /:/, <>' "$rootpath"`
    },
        ($root_path eq '.' ? '`dirname $0`' : '`dirname $0`/'._quote_dq $root_path),
        _quote_dq +File::Spec->abs2rel (get_relative_libs_txt_file_name ($perl_version), $RootDirName),
    ;
  } else {
    $paths = sprintf q{libpaths=`cat %s 2> /dev/null`},
        _quote_dq get_libs_txt_file_name ($perl_version),
    ;
  }
  printf $file qq{\#!/bin/bash
%s
PMBP_ORIG_PATH="%s" PATH="%s" PERL5LIB="\$libpaths" LD_LIBRARY_PATH="%s" exec %s"\$\@"
},
      $paths,
      _quote_dq '${PMBP_ORIG_PATH:-$PATH}',
      _quote_dq (join ':', @bin_path, '${PMBP_ORIG_PATH:-$PATH}'),
      _quote_dq (join ':', @lib_path, '$LD_LIBRARY_PATH'),
      (defined $command ? '"' . $command . '" ' : '') .
      (defined $arg ? '"' . $arg . '" ' : '');
  close $file;
  chmod 0755, $file_name or info_die "$0: $file_name: $!";
} # create_perl_command_shortcut

sub create_perl_command_shortcut_by_file ($$) {
  my ($perl_version, $file_name) = @_;
  info_die "|$file_name| not found" unless -f $file_name;
  open my $file, '<', $file_name or info_die "$file_name: $!";
  while (<$file>) {
    ## See also: |--create-perl-command-shortcut| command
    tr/\x0D\x0A//d;
    if (/^#/) {
      next;
    }

    my %args;
    if (s/^\@//) {
      $args{relocatable} = 1;
    }
    if (/=/) {
      # ../myapp=bin/myapp.pl
      my ($file_name, $command) = split /=/, $_, 2;
      if ($command =~ s/^(\S+)\s+(?=\S)//) {
        # ../myapp=perl bin/myapp.pl
        $command = [$1, $command];
      }
      create_perl_command_shortcut $perl_version, $command => $file_name,
          %args;
      add_to_gitignore ['/'.$file_name] => "$RootDirName/.gitignore";
    } elsif (m{/([^/]+)$}) {
      # local/bin/hoge (== local/bin/hoge=hoge)
      create_perl_command_shortcut $perl_version, $1 => $_, %args;
      add_to_gitignore ['/'.$_] => "$RootDirName/.gitignore";
    } elsif (/^(.+)$/) {
      create_perl_command_shortcut $perl_version, $1 => $1, %args;
      add_to_gitignore ['/'.$1] => "$RootDirName/.gitignore";
    }
  }
} # create_perl_command_shortcut_by_file

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

  my $temp_dir_name = $args{temp_dir_name} || create_temp_dir_name;

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

sub load_deps ($$$;%) {
  my ($module_index, $input_module, $perl_version, %args) = @_;
  my $module = $input_module;
  if (defined $module->version) {
    $module = $module_index->find_by_module ($module) || $module;
  }
  unless (defined $module->distvname) {
    info 2, "distvname of module |@{[$module->as_short]}| is not known";
    return undef;
  }

  my $result = [];

  my @module = ($module);
  my %done;
  while (@module) {
    my $module = shift @module;
    my $dist = $module->distvname;
    next if not defined $dist;
    next if $done{$dist}++;
    my $json_file_name = deps_json_dir_name . "/$dist.json";
    info 2, "Loading |$json_file_name|...";
    unless (-f $json_file_name) {
      info 2, "Module dependency data file |$json_file_name| not found; retry scandeps...";
      scandeps $module_index, $perl_version, $module, %args;
      unless (-f $json_file_name) {
        info 2, "Module dependency data file |$json_file_name| not found; retried but failed";
        return undef;
      }
    }
    my $json = load_json $json_file_name;
    if (defined $json and ref $json eq 'ARRAY') {
      push @module, (PMBP::ModuleIndex->new_from_arrayref ($json->[1])->to_list);
      unshift @$result, PMBP::Module->new_from_jsonalizable ($json->[0]);
    } else {
      info 1, "Module dependency data file |$json_file_name| seems broken";
    }
  }
  return undef unless @$result;
  return $result;
} # load_deps

## ------ Perl module lists ------

sub select_module ($$$$;%) {
  my ($src_module_index => $perl_version, $module => $dest_module_index, %args) = @_;

  unless (defined $module->distvname) {
    info_die "distvname of module |@{[$module->as_short]}| is not known";
  }
  
  my $mods = load_deps $src_module_index => $module, $perl_version, %args;
  unless ($mods) {
    info 0, "Scanning dependency of @{[$module->as_short]}...";
    scandeps $src_module_index, $perl_version, $module, %args;
    $mods = load_deps $src_module_index => $module, $perl_version, %args;
    unless ($mods) {
      if ($module->is_perl) {
        $mods = [];
      } elsif (defined $module->pathname) {
        if (save_by_pathname $module->pathname => $module) {
          scandeps $src_module_index, $perl_version, $module, %args;
          $mods = load_deps $src_module_index => $module, $perl_version, %args;
        }
      } elsif (defined $module->package and defined $module->version) {
        ## This is an unreliable heuristics...
        my $current_module = $src_module_index->find_by_module
            (PMBP::Module->new_from_package ($module->package));
        if ($current_module) {
          my $path = $current_module->pathname;
          if (defined $path and $path =~ s{-[0-9A-Za-z.+-]+\.(tar\.(?:gz|bz2)|zip|tgz)$}{-@{[$module->version]}.$1}) {
            if (save_by_pathname $path => $module) {
              scandeps $src_module_index, $perl_version, $module, %args;
              $mods = load_deps $src_module_index => $module, $perl_version, %args;
            }
          }
        }
      } # version
      info_die "Can't detect dependency of @{[$module->as_short]}\n"
          unless $mods;
    }
  }
  $dest_module_index->merge_modules ($mods);
  for (@$mods) {
    next if $_->package eq $module->package;
    push @{$args{dep_graph} or []}, [$module => $_];
  }
} # select_module

sub read_module_index ($$) {
  my ($file_name => $module_index) = @_;
  my $modules = [];
  push @$modules, map { PMBP::Module->new_from_indexable ($_) }
      (_read_module_index ($file_name));
  $module_index->merge_modules ($modules);
} # read_module_index

sub _read_module_index ($) {
  my ($file_name) = @_;
  unless (-f $file_name) {
    info 0, "$file_name not found; skipped\n";
    return;
  }
  info 2, "Reading module index $file_name...";
  profiler_start 'file';
  open my $file, '<', $file_name or info_die "$0: $file_name: $!";
  my $has_blank_line;
  my @data;
  while (<$file>) {
    if ($has_blank_line) {
      my @d = split /\s+/, $_, 4;
      push @data, \@d if @d >= 3;
    } elsif (/^$/) {
      $has_blank_line = 1;
    }
  }
  profiler_stop 'file';
  info 2, "done";
  return @data;
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

  info_writing 1, "package list", $file_name;
  mkdir_for_file $file_name;
  open my $details, '>', $file_name or info_die "$0: $file_name: $!";
  print $details "File: 02packages.details.txt\n";
  print $details "URL: https://www.perl.com/CPAN/modules/02packages.details.txt\n";
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
  profiler_start 'file';
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
  profiler_stop 'file';
  $module_index->merge_modules ($modules);
  if ($args{dep_graph_source}) {
    push @{$args{dep_graph} or []}, [$args{dep_graph_source}, $_] for @$modules;
  }
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
  for (sort { $a->[0] cmp $b->[0] } @$result) {
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

sub read_pmbp_exclusions_txt ($$) {
  my ($file_name => $defs) = @_;
  if (-d $file_name) {
    $file_name = "$file_name/config/perl/pmbp-exclusions.txt";
  }
  return unless -f $file_name;
  my $base_dir_name = $file_name;
  $base_dir_name =~ s{[^/]+\z}{};
  $base_dir_name =~ s{/\z}{};
  info 2, "Loading |$file_name|...";
  open my $file, '<', $file_name or die "$0: $file_name: $!";
  while (<$file>) {
    if (/^\s*#/) {
      #
    } elsif (/^-\s*"([^"]+)"\s*(.+)$/) {
      my $mod_name = "$base_dir_name/$1";
      if (-d $mod_name) {
        $mod_name = abs_path $mod_name;
        my $components = [split /\s+/, $2];
        if (defined $mod_name) {
          $defs->{components}->{$mod_name}->{$_} = $file_name for @$components;
        }
      }
    } elsif (/^-\s*([0-9A-Za-z:]+)$/) {
      $defs->{modules}->{$1} = $file_name;
    } elsif (/^\s*$/) {
      #
    } else {
      info_die "$file_name: Broken line: $_";
    }
  }
} # read_pmbp_exclusions_txt

sub read_install_list ($$$;%);
sub read_install_list ($$$;%) {
  my ($dir_name => $module_index, $perl_version, %args) = @_;
  $dir_name = abs_path $dir_name;
  info 2, "Examining |$dir_name| ...";

  my $onadd = sub { my $source = shift; return sub {
    info 1, sprintf '|%s| requires |%s|', $source, $_[0]->as_short;
    push @{$args{dep_graph} or []}, [$args{dep_graph_source} => $_[0]]
        if $args{dep_graph_source};
  } }; # $onadd

  THIS: {
    ## pmb install list format
    my @file = map { (glob "$_/config/perl/modules*.txt") } $dir_name;
    if (@file) {
      my $excluded = $args{exclusions}->{components}->{$dir_name};
      if ($excluded) {
        my $regexp = '/config/perl/modules\\.(' . (join '|', map { quotemeta $_ } grep { $excluded->{$_} } keys %$excluded) . ')\\.txt';
        @file = grep {
          if (/$regexp/) {
            info 4, "$_ is excluded by $excluded->{$1}";
            0;
          } else {
            1;
          }
        } @file;
      }
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
           onadd => $onadd->("$dir_name/cpanfile"),
           exclusions => $args{exclusions});
      last THIS;
    }
    
    ## CPAN package configuration scripts
    if (-f "$dir_name/Build.PL" or -f "$dir_name/Makefile.PL") {
      if (-f "$dir_name/Build.PL" and not -f "$dir_name/META.yml") {
        ## Broken by <https://github.com/miyagawa/cpanminus/commit/54f1111211f3fe2f0a35ca41a8664c16ce8305b6>
        info 0, "Generating META.yml...";
        my $envs = {%{get_envs_for_perl ($PerlCommand, $perl_version)},
                    LANG => 'C',
                    MAKEFLAGS => ''};
        {
          my $out = '';
          my $r = run_command
              [$PerlCommand, 'Build.PL'],
              envs => $envs,
              chdir => $dir_name,
              onoutput => sub {
                $out .= $_[0];
              };
          if (not $r) {
            if ($out =~ m{^Can't locate Module/Build.pm}) {
              install_module ($PerlCommand, $perl_version,
                  PMBP::Module->new_from_package ('Module::Build'));
              $envs = {%{get_envs_for_perl ($PerlCommand, $perl_version)},
                       LANG => 'C',
                       MAKEFLAGS => ''};
              run_command
                  [$PerlCommand, 'Build.PL'],
                  envs => $envs,
                  chdir => $dir_name
                  or info_die "Build.PL failed";
            }
          }
        }
        run_command
            [$PerlCommand, 'Build', 'distmeta'],
            envs => $envs,
            chdir => $dir_name
                or info_die "Build distmeta failed";
        info_die "Build distmeta failed" unless -f "$dir_name/META.yml";
      }
      my $temp_dir_name = create_temp_dir_name;
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
      if ($args{exclusions}->{modules}->{$_}) {
        info 6, "Module |$_| excluded by |$args{exclusions}->{modules}->{$_}|";
        next;
      }
      my $mod = PMBP::Module->new_from_package ($_);
      push @$modules, $mod;
      $onadd->($dir_name)->($mod);
    }
    $module_index->merge_modules ($modules);
    last THIS;
  } # THIS

  ## Submodules
  return unless $args{recursive};
  for my $subdir_name (map { glob "$dir_name/$_" } qw(
    modules/* bin/modules/* t_deps/modules/* local/submodules/*
  )) {
    my $short_name = File::Spec->abs2rel ($subdir_name, $dir_name);
    my $source;
    if ($args{dep_graph_source}) {
      if ($args{dep_graph_source}->package eq '.') {
        $source = PMBP::Module->new_from_package ($short_name);
      } else {
        $source = PMBP::Module->new_from_package ($args{dep_graph_source}->package . '/' . $short_name);
      }
    }
    read_install_list $subdir_name => $module_index, $perl_version,
        recursive => $args{recursive} ? $args{recursive} - 1 : 0,
        dep_graph => $args{dep_graph},
        dep_graph_source => $source,
        exclusions => $args{exclusions};
  }
} # read_install_list

sub find_install_list ($;%);
sub find_install_list ($;%) {
  my ($dir_name, %args) = @_;
  my @result;
  $dir_name = abs_path $dir_name;

  my @file = map { (glob "$_/config/perl/modules*.txt") } $dir_name;
  if (@file) {
    my $excluded = $args{exclusions}->{components}->{$dir_name};
    if ($excluded) {
      my $regexp = '/config/perl/modules\\.(' . (join '|', map { quotemeta $_ } grep { $excluded->{$_} } keys %$excluded) . ')\\.txt';
      for my $file_name (@file) {
        push @result, {dir_name => $dir_name,
                       file_name => $file_name,
                       excluded => scalar $file_name =~ /$regexp/};
      }
    } else {
      push @result, {dir_name => $dir_name, file_name => $_}
          for @file;
    }
  } else {
    push @result, {dir_name => $dir_name};
  }

  ## Submodules
  return \@result unless $args{recursive};
  for my $subdir_name (map { glob "$dir_name/$_" } qw(
    modules/* bin/modules/* t_deps/modules/* local/submodules/*
                                                    )) {
    push @result, @{find_install_list $subdir_name, exclusions => $args{exclusions}};
  }
  return \@result;
} # find_install_list

sub print_install_list_list ($) {
  my $list = $_[0];
  my $last_dir_name = '';
  for my $item (sort {
      $a->{dir_name} cmp $b->{dir_name} || $a->{file_name} cmp $b->{file_name};
    } @$list) {
    print +File::Spec->abs2rel ($item->{dir_name}, $RootDirName), "\n"
        if $item->{dir_name} ne $last_dir_name;
    $last_dir_name = $item->{dir_name};
    my $shorten = File::Spec->abs2rel ($item->{file_name}, $item->{dir_name});
    next if $shorten eq 'config/perl/modules.txt';
    $shorten = $1 if $shorten =~ m{\Aconfig/perl/modules\.([^./]+)\.txt\z};
    print '  ', $shorten;
    print "\t(excluded)" if $item->{excluded};
    print "\n";
  }
} # print_install_list_list

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
    if ($args{exclusions}->{modules}->{$_}) {
      info 6, "Module |$_| excluded by |$args{exclusions}->{modules}->{$_}|";
      next;
    } elsif ($_ eq 'perl') {
      next;
    }
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
  my @exclude_pattern = map { "^$_" } qw(modules bin/modules t_deps/modules t_deps/projects);
  for (split /\n/, qx{cd @{[shellarg $dir_name]} && find @{[join ' ', map { shellarg $_ } @include_dir_name]} 2> /dev/null @{[join ' ', map { "| grep -v $_" } map { shellarg $_ } @exclude_pattern]} | grep "\\.\\(pm\\|pl\\|t\\)\$" | xargs grep "\\(use\\|require\\|extends\\) " --no-filename}) {
    s/\#.*$//;
    while (/\b(?:(?:use|require)\s*(?:base|parent)|extends)\s*(.+)/g) {
      my $base = $1;
      while ($base =~ /([0-9A-Za-z_:]+)/g) {
        $modules->{$1} = 1;
      }
    }
    while (/\b(?:use|require)\s*([0-9A-Za-z_:]+)/g) {
      my $name = $1;
      next if $name =~ /["']/;
      $modules->{$name} = 1;
    }
  }

  @include_dir_name = map { glob "$dir_name/$_" } qw(lib t/lib modules/*/lib bin/modules/*/lib t_deps/modules/*/lib);
  for (split /\n/, qx{cd @{[shellarg $dir_name]} && find @{[join ' ', map { shellarg $_ } @include_dir_name]} 2> /dev/null | grep "\\.\\(pm\\|pl\\)\$" | xargs grep "package " --no-filename}) {
    s/\#.*//;
    if (/package\s*([0-9A-Za-z_:]+)/) {
      delete $modules->{$1};
    }
  }

  delete $modules->{$_} for qw(
    q qw qq
    strict warnings base lib encoding utf8 overload
    constant vars integer
    Config
    moco and or on this that the teh
    a an much more
  );
  for (keys %$modules) {
    delete $modules->{$_} unless /\A[0-9A-Za-z_]+(?:::[0-9A-Za-z_]+)*\z/;
    delete $modules->{$_} if /^[0-9._]+$/;
  }

  return $modules;
} # scan_dependency_from_directory

sub write_dep_graph ($$;%) {
  my ($dep_graph => $file_name, %args) = @_;
  my $format = $args{format} || '';
  if ($format eq 'springy') {
    info_writing 0, "dep_graph file", $file_name;
    open my $file, '>', $file_name or die "$0: $file_name: $!";
    print $file q{
      <!DOCTYPE html>
      <title>Dependency</title>
      <script src="https://ajax.googleapis.com/ajax/libs/jquery/1.3.2/jquery.min.js"></script>
      <script src="http://getspringy.com/springy.js"></script>
      <script src="http://getspringy.com/springyui.js"></script>
      <script>
        var graph = new Springy.Graph;
        var nodes = {};
    };
    my $done = {};
    for (@$dep_graph) {
      for ($_->[0]->package, $_->[1]->package) {
        next if $done->{$_};
        printf $file qq{nodes["%s"] = graph.newNode ({label: "%s"});\n},
            $_, $_;
        $done->{$_} = 1;
      }
    }
    for (@$dep_graph) {
      printf $file qq{graph.newEdge (nodes["%s"], nodes["%s"], {});\n},
          $_->[0]->package, $_->[1]->package;
    }
    print $file q{
      jQuery (function () {
        window.springy = jQuery ('#canvas').springy ({
          graph: graph
        });
      });
      </script>
      <canvas id=canvas width=1920 height=1440></canvas>
    };
  } else {
    info_writing 0, "dep_graph file", $file_name;
    open my $file, '>', $file_name or die "$0: $file_name: $!";
    print $file join '', map { $_->[0]->as_short . "\t" . $_->[1]->as_short . "\n" } @$dep_graph;
  }
} # write_dep_graph

## ------ Perl module installation ------

sub install_module ($$$;%) {
  my ($perl_command, $perl_version, $module, %args) = @_;
  get_local_copy_if_necessary $module;
  my $lib_dir_name = $args{pmpp}
      ? pmpp_dir_name : get_pm_dir_name ($perl_version);
  my $force;
  if (has_module ($perl_command, $perl_version, $module, $lib_dir_name)) {
    if ($module->package eq 'Net::SSLeay' and
        (is_net_ssleay_openssl_too_old ($perl_command, $perl_version) or
         not get_openssl_version ($perl_version) eq get_net_ssleay_openssl_version ($perl_command, $perl_version))) {
      my $v1 = get_openssl_version_details ($perl_version);
      my $v2 = get_net_ssleay_openssl_version_details
          ($perl_command, $perl_version);
      info 0, "Reinstall Net::SSLeay (1)...";
      info 0, "Platform OpenSSL:\n----\n" . $v1 . "\n----";
      info 0, "Net::SSLeay OpenSSL:\n----\n" . $v2 . "\n----";
      $force = 1;
    } else {
      info 1, "Module @{[$module->as_short]} is already installed; skipped";
      return;
    }
  }
  cpanm {perl_version => $perl_version,
         perl_lib_dir_name => $lib_dir_name,
         module_index_file_name => $args{module_index_file_name},
         force => $force},
        [$module];

  if ($module->package eq 'Net::SSLeay') {
    my $v1 = get_openssl_version_details ($perl_version);
    my $v2 = get_net_ssleay_openssl_version_details
        ($perl_command, $perl_version);
    info 0, 'Check Net::SSLeay...';
    info 0, "Platform OpenSSL:\n----\n" . $v1 . "\n----";
    info 0, "Net::SSLeay OpenSSL:\n----\n" . $v2 . "\n----";
    if (is_net_ssleay_openssl_too_old ($perl_command, $perl_version) or
        not get_openssl_version ($perl_version) eq get_net_ssleay_openssl_version ($perl_command, $perl_version)) {
      info 0, "Reinstall Net::SSLeay (2)...";
      install_openssl ($perl_version);
      cpanm {perl_version => $perl_version,
             perl_lib_dir_name => $lib_dir_name,
             module_index_file_name => $args{module_index_file_name},
             force => 1},
             [$module];
    }
  }
} # install_module

sub get_module_version ($$$) {
  my ($perl_command, $perl_version, $module) = @_;
  my $package = $module->package;
  return undef unless defined $package;
  
  my $result;
  my $return = run_command
      [$perl_command, '-M' . $package,
       '-e', sprintf 'print $%s::VERSION', $package],
      envs => get_envs_for_perl ($perl_command, $perl_version),
      info_level => 3,
      discard_stderr => 1,
      onoutput => sub {
        $result = $_[0];
        return 3;
      };
  return undef unless $return;
  return $result;
} # get_module_version

my $MMDLoaded;
sub require_module_metadata () {
  return if $MMDLoaded;
  install_pmbp_module PMBP::Module->new_from_package ('Module::Metadata');
  install_pmbp_module PMBP::Module->new_from_package ('version');
  ## Since the currently loaded version of |version| module might be
  ## older than the one required by the |Module::Metadata|, clear the
  ## module's loaded flag.
  delete $INC{'Module/Metadata.pm'};
  delete $INC{'version.pm'};
  require Module::Metadata;
  require version;
  $MMDLoaded = 1;
} # require_module_metadata

sub has_module ($$$$) {
  my ($perl_command, $perl_version, $module, $dir_name) = @_;
  my $package = $module->package;
  return 0 unless defined $package;
  my $version = $module->version;

  my $file_name = $package . '.pm';
  $file_name =~ s{::}{/}g;
  
  my $archname = get_perl_archname $perl_command, $perl_version;
  for (qq{$dir_name/lib/perl5/$archname/$file_name},
       qq{$dir_name/lib/perl5/$file_name},
       map { "$_/$file_name" } (get_perl_core_lib_paths $perl_command, $perl_version)) {
    next unless -f $_;
    return 1 if not defined $version;
    
    require_module_metadata;

    profiler_start 'version_sniffing';
    my $meta = Module::Metadata->new_from_file ($_) or next;
    my $actual_version = $meta->version;
    my $ver = eval { version->new ($version) };
    if (defined $ver and $actual_version >= $ver) {
      profiler_stop 'version_sniffing';
      return 1;
    } else {
      profiler_stop 'version_sniffing';
    }
  }
  
  return 0;
} # has_module

sub get_openssl_branches_by_api () {
  ## This can fail due to GitHub's API rate limits.
  my $json_file_name = "$PMBPDirName/tmp/openssl-branches.json";
  save_url q<https://api.github.com/repos/openssl/openssl/branches> => $json_file_name,
      max_age => 60*60*24*100;
  my $json = load_json $json_file_name;
  unless (defined $json and ref $json eq 'ARRAY') {
    require Data::Dumper;
    info_die "Bad JSON data: " . Data::Dumper::Dumper ($json);
  }
  my @branch;
  for (@$json) {
    if ($_->{name} =~ /^OpenSSL_(\d+)_(\d+)_(\d+)-stable$/) {
      push @branch, [$_->{name}, $1, $2, $3];
    }
  }
  @branch = map { $_->[0] } sort {
    $a->[1] <=> $b->[1] ||
    $a->[2] <=> $b->[2] ||
    $a->[3] <=> $b->[3];
  } @branch;
  unshift @branch, 'master'; # unstable
  return [reverse @branch];
} # get_openssl_branches_by_api

sub get_openssl_branch () {
  my $branch_file_name = "$PMBPDirName/tmp/openssl-branch.txt";
  save_url q<https://raw.githubusercontent.com/wakaba/perl-setupenv/master/version/openssl-stable-branch.txt> => $branch_file_name,
      max_age => 60*60*24*100;
  open my $branch_file, '<', $branch_file_name
      or info_die "Can't open file |$branch_file_name|";
  my $branch = <$branch_file>;
  info_die "Bad branch file |$branch|" unless $branch;
  return $branch;
} # get_openssl_branch

sub get_libressl_stable_branch_by_api () {
  ## This can fail due to GitHub's API rate limits.
  my $branches_url = q<https://api.github.com/repos/libressl-portable/portable/branches>;
  save_url $branches_url => "$PMBPDirName/tmp/libressl-branches.json";
  my $branch_list = load_json "$PMBPDirName/tmp/libressl-branches.json";
  copy_log_file "$PMBPDirName/tmp/libressl-branches.json" => "libressl-branches";
  my @branch;
  info_die "Broken branch list" unless ref $branch_list eq 'ARRAY';
  for (@$branch_list) {
    if ($_->{name} =~ m{^OPENBSD_([0-9]+)_([0-9]+)$}) {
      push @branch, [$1, $2, $_->{name}];
    } else {
      push @branch, [0, 0, $_->{name}];
    }
  }
  @branch = sort { $b->[0] <=> $a->[0] || $b->[1] <=> $a->[1] } @branch;
  return $branch[0]->[2];
} # get_libressl_stable_branch_by_api

sub get_libressl_branch () {
  my $branch_file_name = "$PMBPDirName/tmp/libressl-branch.txt";
  save_url q<https://raw.githubusercontent.com/wakaba/perl-setupenv/master/version/libressl-stable-branch.txt> => $branch_file_name,
      max_age => 60*60*24*100;
  open my $branch_file, '<', $branch_file_name
      or info_die "Can't open file |$branch_file_name|";
  my $branch = <$branch_file>;
  info_die "Bad branch file |$branch|" unless $branch;
  return $branch;
} # get_libressl_branch

my $_OpenSSLVersion = undef;
sub get_openssl_version ($) {
  my ($perl_version) = @_;
  return $_OpenSSLVersion if defined $_OpenSSLVersion;
  my $version;
  run_command
      ['openssl', 'version'],
      envs => {PATH => get_env_path ($perl_version)},
      onoutput => sub { $version = $_[0]; 2 };
  $version =~ s/[\x0D\x0A]+\z// if defined $version;
  return $_OpenSSLVersion = $version;
} # get_openssl_version

sub get_openssl_version_details ($) {
  my ($perl_version) = @_;
  my $version;
  run_command
      ['openssl', 'version', '-a'],
      envs => {PATH => get_env_path ($perl_version)},
      onoutput => sub { $version .= $_[0]; 2 };
  $version =~ s/[\x0D\x0A]+\z// if defined $version;
  return $version;
} # get_openssl_version_details

sub get_net_ssleay_openssl_version ($$) {
  my ($perl_command, $perl_version) = @_;
  my $version;
  run_command
      ['perl', '-MNet::SSLeay', '-e', 'print +Net::SSLeay::SSLeay_version'],
      envs => get_envs_for_perl ($perl_command, $perl_version),
      onoutput => sub { $version = $_[0]; 2 };
  return $version;
} # get_net_ssleay_openssl_version

sub get_net_ssleay_openssl_version_details ($$) {
  my ($perl_command, $perl_version) = @_;
  my $version;
  run_command
      ['perl', '-MNet::SSLeay', '-e', '
        print join "\n",
            Net::SSLeay::SSLeay_version (0),
            Net::SSLeay::SSLeay_version (2),
            Net::SSLeay::SSLeay_version (3),
            Net::SSLeay::SSLeay_version (4),
            $INC{q{Net/SSLeay.pm}},
            $Net::SSLeay::VERSION,
            "";
      '],
      envs => get_envs_for_perl ($perl_command, $perl_version),
      onoutput => sub { $version .= $_[0]; 2 };
  return $version;
} # get_net_ssleay_openssl_version_details

sub is_openssl_too_old ($) {
  my ($perl_version) = @_;
  my $version = get_openssl_version ($perl_version);
  return 1 if not defined $version;
  if ($version =~ /^OpenSSL (?:0\.|1\.0\.)/) {
    return 1;
  }
  return 0;
} # is_openssl_too_old

sub is_net_ssleay_openssl_too_old ($$) {
  my ($perl_command, $perl_version) = @_;
  my $version = get_net_ssleay_openssl_version ($perl_command, $perl_version);
  return 1 if not defined $version;
  if ($version =~ /^OpenSSL (?:0\.|1\.0\.)/) {
    return 1;
  }
  return 0;
} # is_net_ssleay_openssl_too_old

sub install_openssl ($) {
  my ($perl_version) = @_;
  my $common_dir_name = "$RootDirName/local/common";

  if (is_openssl_too_old ($perl_version)) {
    #
  } elsif (-x "$common_dir_name/bin/openssl") {
    info 0, sprintf "There is |$common_dir_name/bin/openssl| (%s)",
        get_openssl_version ($perl_version);
    return 0;
  }

  info 0, "Installing openssl...";
  my $branch = get_libressl_branch;
  my $url = q<https://github.com/libressl-portable/portable>;
  my $max_retry = 10;
  make_path "$PMBPDirName/tmp";
  #my $repo_dir_name = "$PMBPDirName/tmp/openssl";
  my $repo_dir_name = create_temp_dir_name;
  unless (-d "$repo_dir_name/.git") {
    run_command [git, 'clone', $url, $repo_dir_name, '--depth', $max_retry + 2,
                 '-b', $branch]
        or info_die "|git clone| failed";
  } else {
    #run_command [git, 'pull'],
    #    chdir => $repo_dir_name
    #    or info_die "|git pull| failed";
  }

  install_commands ['make', 'gcc'];

  my $temp_dir_name = create_temp_dir_name;
  my $temp_c_file_name = "$temp_dir_name/a.c";
  open my $temp_c_file, '>', $temp_c_file_name
      or info_die "Can't write |$temp_c_file_name|: $!";
  print $temp_c_file q{int main () { }};
  close $temp_c_file;
  unless (run_command ['gcc', '-lz', $temp_c_file_name],
              chdir => $temp_dir_name) {
    if ($PlatformIsMacOSX) {
      xcode_select_install
          or info_die "Failed to install openssl (xcode-select)";
    } else {
      install_system_packages [{name => 'zlib-devel', debian_name => 'zlib1g-dev'}]
          or info_die "Failed to install openssl (zlib-devel)";
    }
  }

  my $autogen_sed_failed = 0;
  my $autogen_failed = 0;
  {
    info 0, "Installing LibreSSL revision:";
    run_command [git, 'rev-parse', 'HEAD'],
        chdir => $repo_dir_name,
        onoutput => sub { 0 };

    my $needs = {};
    my $ok = run_command ['./autogen.sh'],
        chdir => $repo_dir_name,
        envs => {LANG => 'C'},
        onoutput => sub {
          if ($_[0] =~ m{/usr/local/Library/ENV/[^/]+/sed: No such file or directory}) {
            $autogen_sed_failed ||= 1;
          } elsif ($_[0] =~ m{patch: command not found}) {
            $needs->{patch} = 1;
          } elsif ($_[0] =~ m{autoreconf: command not found} or
                   $_[0] =~ m{autoreconf: not found}) {
            $needs->{autoconf} = 1;
            $needs->{automake} = 1; # requires these anyway
            $needs->{libtool} = 1;
          } elsif ($_[0] =~ m{Can't exec "aclocal": No such file or directory}) {
            $needs->{automake} = 1;
          } elsif ($_[0] =~ m{error: possibly undefined macro: AC_PROG_LIBTOOL}) {
#      If this token and others are legitimate, please use m4_pattern_allow.
#      See the Autoconf documentation.
            $needs->{libtool} = 1;
          #} elsif ($_[0] =~ m{/openbsd/src/.+?': No such file or directory}) {
          #} elsif ($_[0] =~ m{\d+ out of \d+ hunks FAILED}) {
          }
          return 6;
        };
    if (not $ok and $autogen_sed_failed == 1) {
      ## <https://github.com/Homebrew/legacy-homebrew/issues/43874>
      run_command ['brew', 'uninstall', 'libtool'] or info 1, "brew failed";
      run_command ['brew', 'install', 'libtool'] or info_die "brew failed";
      $autogen_sed_failed++;
      redo;
    } elsif (not $ok and keys %$needs) {
      install_system_packages [map {
        {
          patch => {name => 'patch'}, # apt, yum
          autoconf => {name => 'autoconf'},
          automake => {name => 'automake'},
          libtool => {name => 'libtool'},
        }->{$_} || info_die "Unknown needs key |$_|";
      } keys %$needs]
          or info_die "Can't install openssl";
      $autogen_failed++;
      redo;
    } elsif (not $ok and $autogen_failed < $max_retry) {
      run_command [git, 'add', '.'],
          chdir => $repo_dir_name;
      run_command [git, 'reset', '--hard'],
          chdir => $repo_dir_name;
      run_command [git, 'checkout', 'HEAD~1'],
          chdir => $repo_dir_name
          or info_die "Failed autogen and git checkout ($autogen_failed)";
      $autogen_failed++;
      redo;
    }
    info_die "Failed autogen" unless $ok;
  }
  run_command ['./configure',
               "--help"],
      chdir => $repo_dir_name
      or info_die "Can't build the package";
  run_command ['./configure',
               "--prefix=$common_dir_name"],
      chdir => $repo_dir_name
      or info_die "Can't build the package";
  run_command ['make'],
      chdir => $repo_dir_name
      or info_die "Can't build the package";
  run_command ['make', 'install'],
      chdir => $repo_dir_name
      or info_die "Can't install the package";
  $_OpenSSLVersion = undef;

  ## Now, |Net::SSLeay| can be compiled and the command:
  ##   $ ./perl -MNet::SSLeay -e 'print +Net::SSLeay::SSLeay_version,"\n"'
  ## ... will output the same value as |./local/common/bin/openssl version|.
  return 1;
} # install_openssl

sub install_openssl_if_too_old ($) {
  my ($perl_version) = @_;
  if (is_openssl_too_old ($perl_version)) {
    my $openssl_version = get_openssl_version_details ($perl_version);
    if (defined $openssl_version) {
      info 0, "Your OpenSSL is too old:\n$openssl_version";
    } else {
      info 0, "You don't have OpenSSL";
    }
    install_openssl ($perl_version);
  } else {
    my $openssl_version = get_openssl_version ($perl_version);
    info 0, "You have OpenSSL |$openssl_version| (not too old)";
  }
} # install_openssl_if_too_old

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
  my $envs = {PATH => get_env_path ($perl_version),
              PERL5LIB => (join ':',
                             ("$install_dir_name/lib/perl5",
                              get_lib_dir_names ($perl_command, $perl_version))),
              MAKEFLAGS => '',
              LANG => 'C'};
  for my $name (qw{ExtUtils::MakeMaker ExtUtils::ParseXS}) {
    my $module = PMBP::Module->new_from_package ($name);
    cpanm {perl_version => $perl_version,
           perl_lib_dir_name => $install_dir_name,
           module_index_file_name => $args{module_index_file_name}},
          [$module];
  }
  my $libperl_so_dir_name;
  run_command
      ['perl', '-MConfig', '-e', 'print $Config{archlib}'],
      chdir => $dir_name,
      envs => $envs,
      onoutput => sub { $libperl_so_dir_name = "$_[0]/CORE"; 4 }
          or info_die "Can't find |libperl.so| directory";
  unless (-f "$libperl_so_dir_name/libperl.so") {
    info 0, "You don't have |libperl.so|";
  }
  my $retry_count = 0;
  A: {
    my $retry;
    my @required_system;
    my @required_installable;
    my $onoutput = sub {
      my $log = $_[0];
      if ($log =~ m{ld: cannot find -lperl}m) {
        push @required_system,
            {name => 'perl-devel',
             redhat_name => 'perl-libs',
             debian_name => 'libperl-dev'};
        $retry = 1;
      } elsif ($log =~ /\bsh: 1: cc: not found$/m or
               $log =~ /^configure: error: no acceptable C compiler found/m) {
        push @required_installable, 'gcc';
      }
      return 1;
    };
    my $install = sub {
      return 0 unless $retry;
      return 0 if $retry_count++ > 5;
      return 0 unless install_system_packages \@required_system;
      install_commands \@required_installable;
      return 1;
    };
    run_command
        ['sh', 'configure',
         '--with-perl',
         '--with-perl-options=INSTALL_BASE="' . $install_dir_name . '" CCFLAGS="-I.."',
         '--prefix=' . $install_dir_name,
         '--without-lcms2'],
        onoutput => $onoutput,
        prefix => "configure($retry_count)",
        chdir => $dir_name,
        envs => $envs,
            or do {
              redo A if $install->();
              info_die "ImageMagick ./configure failed";
            };
    run_command
        ['make', 'INST_DYNAMIC_FIX=-L'.$libperl_so_dir_name],
        onoutput => $onoutput,
        prefix => "make($retry_count)",
        chdir => $dir_name,
        envs => $envs,
            or do {
              redo A if $install->();
              info_die "ImageMagick make failed";
            };
    run_command
        ['make', 'install', 'INST_DYNAMIC_FIX=-L'.$libperl_so_dir_name],
        onoutput => $onoutput,
        prefix => "make install($retry_count)",
        chdir => $dir_name,
        envs => $envs,
            or do {
              redo A if $install->();
              info_die "ImageMagick make install failed";
            };
  } # A
  remove_tree $container_dir_name;
  return 1;
} # build_imagemagick

## ------ Apache ------

sub get_latest_apr_versions () {
  my $file_name = qq<$PMBPDirName/apr.html>;
  save_url q<https://apr.apache.org/download.cgi> => $file_name
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
                  _mirror => 'https://www.apache.org/dist/'};

  if ($html =~ /APR ([0-9.]+) is the best available version/) {
    $versions->{apr} = $1;
  }
  if ($html =~ /APR-util ([0-9.]+) is the best available version/) {
    $versions->{'apr-util'} = $1;
  }
  if ($html =~ m{The currently selected mirror is <b>(https?://[^<]+)</b>.}) {
    $versions->{_mirror} = $1;
  }
  
  return $versions;
} # get_latest_apr_versions

sub get_latest_apache_httpd_versions () {
  my $file_name = qq<$PMBPDirName/apache-httpd.html>;
  save_url q<https://httpd.apache.org/download.cgi> => $file_name
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
                  'httpd-2.2' => '2.2.29',
                  'httpd-2.0' => '2.0.64',
                  _mirror => 'https://www.apache.org/dist/'};

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
  if ($html =~ m{The currently selected mirror is <b>(https?://[^<]+)</b>.}) {
    $versions->{_mirror} = $1;
  }
  
  return $versions;
} # get_latest_apache_httpd_versions

sub get_latest_svn_versions () {
  my $file_name = qq<$PMBPDirName/svn.html>;
  save_url q<https://subversion.apache.org/download/> => $file_name
      if not -f $file_name or
         [stat $file_name]->[9] + 24 * 60 * 60 < time;

  my $html;
  {
    open my $file, '<', $file_name or die "$0: $file_name: $!";
    local $/ = undef;
    $html = scalar <$file>;
    $html =~ s/&nbsp;/ /g;
    $html =~ s/\s+/ /g;
  }

  my $versions = {subversion => '1.9.3',
                  _mirror => 'https://www.apache.org/dist/'};

  if ($html =~ m{The best available version of Apache Subversion is:\s*(?:<a [^<>]*>|)([0-9.]+)(?:</a>|)}) {
    $versions->{subversion} = $1;
  }
  if ($html =~ m{The currently selected mirror is <a\s*href=[^>]+>\s*<b>(https?://[^<]+)</b>\s*</a>.}) {
    $versions->{_mirror} = $1;
  }
  
  return $versions;
} # get_latest_svn_versions

sub save_apache_package ($$$) {
  my ($mirror_url => $package_name, $version) = @_;
  my $file_name = pmtar_dir_name . "/packages/apache/$package_name-$version.tar.gz";
  
  my $url_dir_name = {'apr-util' => 'apr'}->{$package_name} || $package_name;
  for my $mirror ($mirror_url,
                  "https://www.apache.org/dist/",
                  "https://archive.apache.org/dist/") {
    next unless defined $mirror;
    if (-s $file_name) {
      info 7, "|$file_name| found";
      last;
    }
    _save_url "$mirror$url_dir_name/$package_name-$version.tar.gz"
        => $file_name;
  }
  
  info_die "Can't download $package_name $version"
      unless -s $file_name;
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
  my $url = "https://archive.apache.org/dist/httpd/apache_$version.tar.gz";
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
               '--target=httpd', # otherwise this can be "modperl"
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

sub install_svn () {
  my $dest_dir_name = "$RootDirName/local/apache/svn";

  if (-x "$dest_dir_name/bin/svn") {
    info 2, "svn is already installed";
    return;
  }

  info 0, "Installing svn...";

  my $svn_versions = get_latest_svn_versions;
  my $svn_version = $svn_versions->{subversion};
  my $apr_versions = get_latest_apr_versions;
  info 0, "Apache Subversion $svn_version";
  info 0, "  with APR $apr_versions->{apr}";
  info 0, "  with APR-util $apr_versions->{'apr-util'}";
  save_apache_package $svn_versions->{_mirror} => 'subversion', $svn_version;
  save_apache_package $apr_versions->{_mirror}
      => 'apr', $apr_versions->{apr};
  save_apache_package $apr_versions->{_mirror}
      => 'apr-util', $apr_versions->{'apr-util'};
  my $svn_tarball = pmtar_dir_name . "/packages/apache/subversion-$svn_version.tar.gz";
  my $apr_tarball = pmtar_dir_name . "/packages/apache/apr-$apr_versions->{apr}.tar.gz";
  my $apu_tarball = pmtar_dir_name . "/packages/apache/apr-util-$apr_versions->{'apr-util'}.tar.gz";
  my $sqlite_name = qq<sqlite-amalgamation-3071501>;
  my $sqlite_zip = pmtar_dir_name . "/packages/$sqlite_name.zip";
  save_url qq<https://www.sqlite.org/$sqlite_name.zip> => $sqlite_zip;

  my $container_dir_name = "$PMBPDirName/tmp/" . int rand 100000;
  make_path $container_dir_name;
  run_command
      ['unzip', $sqlite_zip],
      chdir => $container_dir_name;
  my $sqlite_dir_name = "$container_dir_name/$sqlite_name";
  info_die "Can't extract sqlite source" unless -d $sqlite_dir_name;

  install_tarball ($apr_tarball => 'apache' => $dest_dir_name,
                   check => sub {
                     return -x "$dest_dir_name/bin/apr-1-config";
                   });
  install_tarball ($apu_tarball => 'apache' => $dest_dir_name,
                   configure_args => [
                     '--with-apr=' . $dest_dir_name,
                   ],
                   check => sub {
                     return -x "$dest_dir_name/bin/apu-1-config";
                   });
  install_tarball ($svn_tarball => 'apache' => $dest_dir_name,
                   before_configure => sub {
                     my $dir_name = $_[0];
                     run_command
                         ['mv', $sqlite_dir_name => qq<$dir_name/sqlite-amalgamation>]
                             or info_die "Can't prepare sqlite-amalgamation";
                   },
                   configure_args => [
                     '--with-apr=' . $dest_dir_name,
                     '--with-apr-util=' . $dest_dir_name,
                   ],
                   check => sub {
                     return -x "$dest_dir_name/bin/svn";
                   });
} # install_svn

sub install_tarball ($$$;%) {
  my ($src_url => $package_category => $dest_dir_name, %args) = @_;
  $src_url = [$src_url] unless ref $src_url eq 'ARRAY';
  my $name = $args{name};
  if (not $name and $src_url->[0] =~ /([0-9A-Za-z_.-]+)\.tar\.gz$/) {
    $name = $1;
  }
  info_die "No package name specified" unless $name;

  if ($args{check} and $args{check}->()) {
    info 2, "Package $name already installed";
    return 1;
  }

  info 0, "Installing $name...";
  my $src_dir_name;
  my @container_dir_name;
  for my $src_url (@$src_url) {
    my $tar_file_name = pmtar_dir_name . "/packages/$package_category/$name.tar.gz";
    if (-f $src_url) {
      $tar_file_name = $src_url;
    } else {
      unless (-f $tar_file_name) {
        unless (_save_url $src_url => $tar_file_name) {
          info 0, "Failed to download <$src_url>";
          next;
        }
      }
    }
    
    my $container_dir_name = "$PMBPDirName/tmp/" . int rand 100000;
    push @container_dir_name, $container_dir_name;
    make_path $container_dir_name;
    if (run_command ['tar', 'zxf', $tar_file_name], chdir => $container_dir_name) {
      $src_dir_name = "$container_dir_name/$name";
      last;
    } else {
      info 0, "Can't expand |$tar_file_name| (renamed as |$tar_file_name.broken|)";
      rename $tar_file_name => "$tar_file_name.broken";
      next;
    }
  } # $src_url
  unless (defined $src_dir_name) {
    info_die "Failed to install tarball |$name|";
  }

  $args{before_configure}->($src_dir_name) if $args{before_configure};

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

  remove_tree $_ for @container_dir_name;

  return $args{check} ? $args{check}->() : 1;
} # install_tarball

## ------ MeCab ------

sub mecab_version () {
  return '0.996';
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
  my $dest_dir_name = "$RootDirName/local/mecab-@{[mecab_version]}-@{[mecab_charset]}";
  
  install_commands ['g++'];
  
  return 0 unless install_tarball
      q<https://drive.google.com/uc?export=download&id=0B4y35FiV1wh7cENtOXlicTFaRUE>
      => 'mecab' => $dest_dir_name,
      name => 'mecab-' . mecab_version,
      configure_args => [
        '--with-charset=' . $mecab_charset,
      ],
      check => sub { -x "@{[mecab_bin_dir_name]}/mecab-config" };
  return install_tarball [
    q<https://drive.google.com/uc?export=download&id=0B4y35FiV1wh7MWVlSDBCSXZMTXM>,
    q<https://downloads.sourceforge.net/project/mecab/mecab-ipadic/2.7.0-20070801/mecab-ipadic-2.7.0-20070801.tar.gz>,
  ] => 'mecab' => $dest_dir_name,
      name => 'mecab-ipadic-2.7.0-20070801',
      configure_args => [
        #  --with-dicdir=DIR  set dicdir location
        '--with-charset=' . $mecab_charset,
        "--with-mecab-config=" . mecab_config_file_name,
      ],
      check => sub {
        return -f "@{[mecab_lib_dir_name]}/mecab/dic/ipadic/sys.dic";
      };
} # install_mecab

## ------ Docker ------

sub before_apt_for_docker () {
  ## <https://docs.docker.com/engine/installation/linux/docker-ce/debian/>
  
  unless (which 'lsb_release') {
    install_system_packages [{name => 'software-properties-common'}]
        or info_die "Failed to install docker (lsb_release)";
  }
  my $id = '';
  my $result = run_command ['lsb_release', '-cs'],
      onoutput => sub { $id .= $_[0] if defined $_[0]; 2 }
      or info_die "Failed to install docker (lsb_release)";
  chomp $id;

  my $os = '';
  run_command ['bash', '-c', '. /etc/os-release; echo "$ID"'],
      onoutput => sub { $os .= $_[0] if defined $_[0]; 2 }
      or info_die "Failed to install docker (os-release)";
  chomp $os;

  unless (_save_url qq<https://download.docker.com/linux/$os/dists/$id/> => "$PMBPDirName/tmp/dummy." . rand) {
    info 1, "There is no docker apt repository for $os $id";
    ## This need to be updated when a new version is available...
    if ($os eq 'debian') {
      $id = 'stretch';
    } elsif ($os eq 'ubuntu') {
      $id = 'xenial';
    } else {
      info_die "Failed to install docker ($os $id not supported)";
    }
  }
  
  my $commands = construct_install_system_packages_commands
      [{name => 'apt-transport-https'},
       {name => 'ca-certificates'},
       {name => 'gnupg2'}];

  my $temp_file_name = "$PMBPDirName/tmp/docker-apt-key";
  save_url
      qq<https://download.docker.com/linux/$os/gpg> => $temp_file_name,
      max_age => 24*60*60;
  push @$commands,
      [{}, wrap_by_sudo ['apt-key', 'add', $temp_file_name], undef, sub { }, undef];

  my $arch = 'amd64';
  push @$commands,
      [{}, wrap_by_sudo ['add-apt-repository',
                         "deb [arch=$arch] https://download.docker.com/linux/$os $id stable"],
       undef, sub { }, undef];

  push @$commands,
      [{}, wrap_by_sudo [$AptGetCommand, 'update'], undef, sub { }, 'network'];
  
  return $commands;
} # before_apt_for_docker

sub before_yum_for_docker () {
  ## <https://docs.docker.com/engine/installation/linux/docker-ce/centos/>

  my $commands = construct_install_system_packages_commands
      [{name => 'yum-utils'},
       {name => 'device-mapper-persistent-data'},
       {name => 'lvm2'}];
  push @$commands,
      [{}, wrap_by_sudo ['yum-config-manager', '--add-repo',
                         'https://download.docker.com/linux/centos/docker-ce.repo'],
       undef, sub { }, undef];

  return $commands;
} # before_yum_for_docker

sub after_brew_for_docker () {
  my $commands;
  push @$commands, [{}, ['open', '/Applications/Docker.app'],
                    undef, sub { }, undef];
  return $commands;
} # after_brew_for_docker

## ------ Perl application ------

sub install_perl_app ($$$;%) {
  my ($perl_command, $perl_version, $url, %args) = @_;

  my $sha;
  if ($url =~ s/\#(.*)$//s) {
    $sha = $1 if length $1;
  }

  my $gh_user;
  my $gh_name;
  if ($url =~ m{^git\@github.com:([^./]+)/([^./]+)}) {
    $gh_user = $1;
    $gh_name = $2;
  } elsif ($url =~ m{^git://github.com/([^./]+)/([^./]+)}) {
    $gh_user = $1;
    $gh_name = $2;
  } elsif ($url =~ m{^https://github.com/([^./]+)/([^./]+)}) {
    $gh_user = $1;
    $gh_name = $2;
  }
  if (defined $gh_user) {
    $url = qq<https://github.com/$gh_user/$gh_name>;
  }

  my $name = $args{name};
  if (not defined $name) {
    if ($url =~ m{([0-9A-Za-z_-]+)(?:\.git)?$}) {
      $name = $1;
    } else {
      $name = 'application';
    }
  }

  my $dir_name = qq{$RootDirName/local/$name};
  unless (-d $dir_name and -d "$dir_name/.git") {
    run_command [git, 'clone', $url, $dir_name, (defined $sha ? () : ('--depth', 1))]
        or info_die "|git clone| failed";
  }

  info 0, "Installing <$url> into |$dir_name|...";

  run_command [git, 'pull'], chdir => $dir_name
      or info_die "|$name|: |git pull| failed";
  if (defined $sha) {
    run_command [git, 'checkout', $sha], chdir => $dir_name
        or info_die "|$name|: |git checkout $sha| failed";
  }

  run_command ['make', '-q', 'deps'], chdir => $dir_name,
      '$?' => \my $deps;
  if (($deps >> 8) == 0 or ($deps >> 8) == 1) {
    # $ make deps
    run_command ['make', 'deps'], chdir => $dir_name,
        envs => {PMBP_VERBOSE => 100},
        info_level => 5
        or info_die "|$name|: |make deps| failed";
  } elsif (-f "$dir_name/cpanfile") {
    # $ carton install
    my $carton_command = "$dir_name/carton";
    unless (-x $carton_command) {
      info 0, 'Installing carton...';
      install_module $perl_command, $perl_version,
          PMBP::Module->new_from_package ('Carton'),
          module_index_file_name => $args{module_index_file_name};

      write_libs_txt $perl_command, $perl_version
          => get_libs_txt_file_name ($perl_version);

      create_perl_command_shortcut $perl_version,
          'carton' => $carton_command;
    }

    info 0, 'Carton install...';
    run_command [$carton_command, 'install'], chdir => $dir_name,
        envs => {PERL5LIB => ''},
        onoutput => sub {
          if ($_[0] =~ m{Installing Coro failed. See (\S+) for details. Retry with --force to force install it.}) {
            copy_log_file $1 => 'carton';
          }
          return $_[0] =~ /^! / ? 0 : 1;
        },
        or info_die "|$name|: |carton install| failed";
  } elsif (-f "$dir_name/Makefile.PL") {
    run_command [git, 'submodule', 'update', '--init'],
        chdir => $dir_name
        or info_die "|$name|: |git submodule update --init| failed";
    ## Invoke pmbp.pl recursively
    run_command [$^X, abs_path ($0), '--install',
                 '--dump-info-file-before-die'],
        chdir => $dir_name
        or info_die "|$name|: --install failed";
  } else {
    info_die "|$name| is not installable";
  }
} # install_perl_app

sub install_perldoc () {
  unless (run_command ['perldoc', 'perldoc']) {
    install_system_packages ([{name => 'perldoc', debian_name => 'perl-doc'}])
        or info_die "Failed to install perldoc";
  }
} # install_perldoc

## ------ Python applications ------

sub install_pip () {
  return if which 'pip';

  my $commands = [];
  unless (which 'python3') {
    $commands = construct_install_system_packages_commands
        [{name => 'python3'}, {name => 'python3-distutils'}];
    #ModuleNotFoundError: No module named 'distutils.cmd'
  }

  my $temp_file_name = "$PMBPDirName/tmp/get-pip.py";
  save_url
      qq<https://bootstrap.pypa.io/get-pip.py> => $temp_file_name,
      max_age => 24*60*60;

  push @$commands, [{}, (wrap_by_sudo ['python3', $temp_file_name]),
                    'Installing pip', sub { }, 'packagemanager'];

  run_system_commands $commands;

  info_die "Failed to install pip" unless which 'pip';
} # install_pip

sub install_awscli () {
  return if run_command ['aws', '--version'];
  
  install_pip;

  my $commands = [];
  push @$commands, [{}, (wrap_by_sudo ['pip', 'install', 'awscli']),
                    'Installing awscli', sub { }, 'packagemanager'];
  run_system_commands $commands;

  info_die "Failed to install awscli" unless run_command ['aws', '--version'];
} # install_awscli

## ------ Cleanup ------

sub destroy () {
  destroy_cpanm_home;
} # destroy

## ------ Main ------

my $global_module_index = PMBP::ModuleIndex->new_empty;
my $selected_module_index = PMBP::ModuleIndex->new_empty;
my $module_index_file_name;
my $pmpp_touched;
open_info_file;
profiler_start 'all';
init_pmbp;
for my $env (qw(PATH PERL5LIB PERL5OPT)) {
  info 6, $env . '=' . (defined $ENV{$env} ? $ENV{$env} : '');
}
info 6, '$ ' . join ' ', $0, @Argument;
info 6, sprintf '%s %vd (%s / %s)', $^X, $^V, $Config{archname}, $^O;
info 6, '@INC = ' . join ' ', @INC;
info 6, '$RootDirName=' . $RootDirName;
my $perl_version;
my $get_perl_version = sub {
  if (defined $SpecifiedPerlVersion) {
    info 6, "Use specified perl version: |$SpecifiedPerlVersion|";
    $perl_version = init_perl_version $SpecifiedPerlVersion;
  } elsif (-f "$RootDirName/config/perl/version.txt") {
    info 6, "Use perl version from config/perl/version.txt";
    $perl_version = init_perl_version_by_file_name "$RootDirName/config/perl/version.txt";
  } else {
    info 6, "Use default perl version";
    $perl_version = init_perl_version undef;
  }
  info 1, "Target Perl version: $perl_version";
}; # $get_perl_version;
my $dep_graph = [];
my $exclusions = {};
my $root_module = PMBP::Module->new_from_package ('.');

{
  ## Check the clock of the machine.  If its value is wrong, some of
  ## building process, such as |make|, might not work because of
  ## failure of timestamp comparison.
  info 1, "There is no |Time::HiRes|: |$TimeHiResError|"
      if defined $TimeHiResError;
  my $time = time;
  my $timestamp = get_real_time;
  if (defined $timestamp) {
    my $delta = $time - $timestamp;
    $delta = -$delta if $delta < 0;
    if ($delta > 60*10) {
      info 0, sprintf "Your clock is misconfigured! (Yours = %s, Global = %s, Delta = %s)",
          $time, $timestamp, $delta;
    } else {
      info 6, sprintf "Your clock seems good (Yours = %s, Global = %s, Delta = %s)",
          $time, $timestamp, $delta;
    }
  }
}

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
        {type => 'read-pmbp-exclusions-txt'},
        {type => 'select-modules-by-list'},
        {type => 'unselect-excluded-modules'},
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
        {type => 'read-pmbp-exclusions-txt'},
        {type => 'install-modules-by-list',
         file_name => -f $pmb_install_file_name
                          ? $pmb_install_file_name : undef},
        {type => 'rewrite-pm-bin-shebang'},
        {type => 'write-libs-txt'},
        {type => 'write-relative-libs-txt'},
        {type => 'create-libs-txt-symlink'},
        {type => 'create-local-perl-latest-symlink'},
        {type => 'create-perl-command-shortcut',
         file_name => 'local/bin/perl', command => 'perl'},
        {type => 'create-perl-command-shortcut',
         file_name => 'local/bin/prove', command => 'prove'},
        {type => 'create-perl-command-shortcut',
         file_name => 'local/bin/perldoc', command => 'perldoc'},
        {type => 'create-perl-command-shortcut-by-list'},
        {type => 'update-gitignore'};

    unless ($ENV{PMBP_NO_PERL_INSTALL}) {
      unshift @Command, {type => 'create-perlbrew-perl-latest-symlink'};
      unshift @Command, {type => 'install-perl-if-necessary'};
    }

    info 1, sprintf "Selected CPAN mirror: <%s>", get_cpan_top_url;

  } elsif ($command->{type} eq 'print-pmbp-pl-etag') {
    my $etag = get_pmbp_pl_etag;
    print $etag if defined $etag;
  } elsif ($command->{type} eq 'update-pmbp-pl') {
    update_pmbp_pl ($command->{branch});
  } elsif ($command->{type} eq 'create-bootstrap-script') {
    create_bootstrap_script
        ($command->{template_file_name}, $command->{result_file_name});

  } elsif ($command->{type} eq 'update-gitignore') {
    update_gitignore;
  } elsif ($command->{type} eq 'add-to-gitignore') {
    add_to_gitignore [$command->{value}] => "$RootDirName/.gitignore";
  } elsif ($command->{type} eq 'init-git-repository') {
    init_git_repository $RootDirName;

  } elsif ($command->{type} eq 'add-git-submodule') {
    add_git_submodule $RootDirName, $command->{url},
        parent_dir_name => $command->{parent_dir_name},
        recursive => $command->{recursive},
        top_level => 1;

  } elsif ($command->{type} eq 'install-commands') {
    install_commands $command->{value};
  } elsif ($command->{type} eq 'install-openssl') {
    $get_perl_version->() unless defined $perl_version;
    install_openssl ($perl_version);
  } elsif ($command->{type} eq 'install-openssl-if-old' or
           $command->{type} eq 'install-openssl-if-mac') {
    $get_perl_version->() unless defined $perl_version;
    install_openssl_if_too_old ($perl_version);
  } elsif ($command->{type} eq 'print-openssl-version') {
    $get_perl_version->() unless defined $perl_version;
    my $ver = get_openssl_version ($perl_version);
    print $ver if defined $ver;
  } elsif ($command->{type} eq 'print-openssl-stable-branch') {
    my $branches = get_openssl_branches_by_api;
    print $branches->[0];
  } elsif ($command->{type} eq 'print-libressl-stable-branch') {
    print get_libressl_stable_branch_by_api;

  } elsif ($command->{type} eq 'print-cpan-top-url') {
    print get_cpan_top_url;
  } elsif ($command->{type} eq 'print-latest-perl-version') {
    print get_latest_perl_version;
  } elsif ($command->{type} eq 'print-selected-perl-version') {
    $get_perl_version->() unless defined $perl_version;
    print $perl_version;
  } elsif ($command->{type} eq 'print-perl-archname') {
    $get_perl_version->() unless defined $perl_version;
    print get_perl_archname $PerlCommand, $perl_version;
  } elsif ($command->{type} eq 'install-perl') {
    $get_perl_version->() unless defined $perl_version;
    info 0, "Installing Perl $perl_version...";
    install_perl $perl_version;
  } elsif ($command->{type} eq 'install-perl-if-necessary') {
    my $actual_perl_version = get_perl_version $PerlCommand || '?';
    $get_perl_version->() unless defined $perl_version;
    unless ($actual_perl_version eq $perl_version) {
      info 0, "Installing Perl $perl_version...";
      install_perl $perl_version;
    }
  } elsif ($command->{type} eq 'create-perlbrew-perl-latest-symlink') {
    $get_perl_version->() unless defined $perl_version;
    create_perlbrew_perl_latest_symlink $perl_version;

  } elsif ($command->{type} eq 'install-module') {
    $get_perl_version->() unless defined $perl_version;
    hide_pmpp_arch_dir $PerlCommand, $perl_version if $pmpp_touched;
    info 0, "Installing @{[$command->{module}->as_short]}...";
    install_module $PerlCommand, $perl_version, $command->{module},
        module_index_file_name => $module_index_file_name;
  } elsif ($command->{type} eq 'install-modules-by-list') {
    $get_perl_version->() unless defined $perl_version;
    hide_pmpp_arch_dir $PerlCommand, $perl_version if $pmpp_touched;
    my $module_index = PMBP::ModuleIndex->new_empty;
    if (defined $command->{file_name}) {
      read_pmb_install_list $command->{file_name} => $module_index;
    } elsif (defined $command->{dir_name}) {
      if (-f "$command->{dir_name}/config/perl/pmb-install.txt") {
        read_pmb_install_list "$command->{dir_name}/config/perl/pmb-install.txt" => $module_index;
      } else {
        read_install_list $command->{dir_name} => $module_index, $perl_version,
            recursive => 1, exclusions => $exclusions;
      }
    } else {
      read_install_list $RootDirName => $module_index, $perl_version,
          recursive => 1, exclusions => $exclusions;
    }
    $module_index->filter_modules_by_exclusions ($exclusions);
    for ($module_index->to_list) {
      info 0, "Installing @{[$_->as_short]}...";
      install_module $PerlCommand, $perl_version, $_,
          module_index_file_name => $module_index_file_name;
    }
  } elsif ($command->{type} eq 'install-to-pmpp') {
    $get_perl_version->() unless defined $perl_version;
    info 0, "Installing @{[$command->{module}->as_short]} to pmpp...";
    install_module $PerlCommand, $perl_version, $command->{module},
        module_index_file_name => $module_index_file_name, pmpp => 1;
    $pmpp_touched = 1;
  } elsif ($command->{type} eq 'install-by-pmpp') {
    $get_perl_version->() unless defined $perl_version;
    info 0, "Copying pmpp modules...";
    copy_pmpp_modules $PerlCommand, $perl_version;
  } elsif ($command->{type} eq 'update-pmpp-by-list') {
    $get_perl_version->() unless defined $perl_version;
    my $module_index = PMBP::ModuleIndex->new_empty;
    if (defined $command->{file_name}) {
      read_pmb_install_list $command->{file_name} => $module_index;
    } else {
      read_install_list $RootDirName => $module_index, $perl_version,
          recursive => 1, exclusions => $exclusions;
    }
    for ($module_index->to_list) {
      info 0, "Installing @{[$_->as_short]} to pmpp...";
      install_module $PerlCommand, $perl_version, $_,
          module_index_file_name => $module_index_file_name, pmpp => 1;
    }
    $pmpp_touched = 1;
  } elsif ($command->{type} eq 'scandeps') {
    $get_perl_version->() unless defined $perl_version;
    info 0, "Scanning dependency of @{[$command->{module}->as_short]}...";
    scandeps $global_module_index, $perl_version, $command->{module},
        skip_if_found => 1,
        module_index_file_name => $module_index_file_name;
  } elsif ($command->{type} eq 'select-module') {
    $get_perl_version->() unless defined $perl_version;
    select_module $global_module_index =>
        $perl_version, $command->{module} => $selected_module_index,
        module_index_file_name => $module_index_file_name,
        dep_graph => $dep_graph;
    $global_module_index->merge_module_index ($selected_module_index);
    push @$dep_graph, [$root_module, $command->{module}];
  } elsif ($command->{type} eq 'select-modules-by-list') {
    $get_perl_version->() unless defined $perl_version;
    my $module_index = PMBP::ModuleIndex->new_empty;
    if (defined $command->{file_name}) {
      read_pmb_install_list $command->{file_name} => $module_index,
          dep_graph_source => $root_module,
          dep_graph => $dep_graph;
    } else {
      read_install_list $RootDirName => $module_index, $perl_version,
          recursive => 1,
          dep_graph_source => $root_module,
          dep_graph => $dep_graph,
          exclusions => $exclusions;
    }
    select_module $global_module_index =>
        $perl_version, $_ => $selected_module_index,
        module_index_file_name => $module_index_file_name,
        dep_graph => $dep_graph
        for ($module_index->to_list);
    $global_module_index->merge_module_index ($selected_module_index);
  } elsif ($command->{type} eq 'read-module-index') {
    read_module_index $command->{file_name} => $global_module_index;
  } elsif ($command->{type} eq 'read-carton-lock') {
    read_carton_lock $command->{file_name} => $global_module_index;
  } elsif ($command->{type} eq 'read-pmbp-exclusions-txt') {
    my $fn = defined $command->{file_name} ? $command->{file_name} : $RootDirName;
    read_pmbp_exclusions_txt $fn => $exclusions;
  } elsif ($command->{type} eq 'unselect-excluded-modules') {
    $selected_module_index->filter_modules_by_exclusions ($exclusions);
  } elsif ($command->{type} eq 'write-module-index') {
    write_module_index $global_module_index => $command->{file_name};
  } elsif ($command->{type} eq 'write-pmb-install-list') {
    write_pmb_install_list $selected_module_index => $command->{file_name};
  } elsif ($command->{type} eq 'write-install-module-index') {
    write_install_module_index $selected_module_index => $command->{file_name};
  } elsif ($command->{type} eq 'write-libs-txt') {
    $get_perl_version->() unless defined $perl_version;
    my $file_name = $command->{file_name};
    $file_name = get_libs_txt_file_name ($perl_version)
        unless defined $file_name;
    write_libs_txt $PerlCommand, $perl_version => $file_name;
  } elsif ($command->{type} eq 'write-relative-libs-txt') {
    $get_perl_version->() unless defined $perl_version;
    my $file_name = $command->{file_name};
    $file_name = get_relative_libs_txt_file_name ($perl_version)
        unless defined $file_name;
    write_relative_libs_txt $PerlCommand, $perl_version => $file_name;
  } elsif ($command->{type} eq 'create-libs-txt-symlink') {
    $get_perl_version->() unless defined $perl_version;
    my $real_name = get_libs_txt_file_name ($perl_version);
    my $link_name = "$RootDirName/config/perl/libs.txt";
    info_writing 3, 'libs.txt symlink', $link_name;
    mkdir_for_file $link_name;
    (unlink $link_name or info_die "$0: $link_name: $!")
        if -f $link_name || -l $link_name;
    (symlink $real_name => $link_name) or info_die "$0: $link_name: $!";
  } elsif ($command->{type} eq 'create-local-perl-latest-symlink') {
    $get_perl_version->() unless defined $perl_version;
    my $real_name = "$RootDirName/local/perl-$perl_version";
    my $link_name = "$RootDirName/local/perl-latest";
    info_writing 3, 'perl-latest symlink', $link_name;
    make_path $real_name;
    remove_tree $link_name;
    symlink $real_name => $link_name or info_die "$0: $link_name: $!";
  } elsif ($command->{type} eq 'create-perl-command-shortcut') {
    $get_perl_version->() unless defined $perl_version;
    create_perl_command_shortcut $perl_version,
        $command->{command} => $command->{file_name},
        %{$command->{args} or {}};
  } elsif ($command->{type} eq 'create-perl-command-shortcut-by-list') {
    my $file_name = "$RootDirName/config/perl/pmbp-shortcuts.txt";
    if (-f $file_name) {
      create_perl_command_shortcut_by_file $perl_version, $file_name;
    }
  } elsif ($command->{type} eq 'rewrite-pm-bin-shebang') {
    rewrite_pm_bin_shebang $perl_version;

  } elsif ($command->{type} eq 'create-pmbp-makefile') {
    save_url $MakefileURL => $command->{value};
  } elsif ($command->{type} eq 'write-makefile-pl') {
    mkdir_for_file $command->{file_name};
    open my $file, '>', $command->{file_name}
        or info_die "$0: $command->{file_name}: $!";
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
    $get_perl_version->() unless defined $perl_version;
    print join ':', (get_lib_dir_names ($PerlCommand, $perl_version));
  } elsif ($command->{type} eq 'set-module-index') {
    $module_index_file_name = $command->{file_name}; # or undef
    PMBP::Module->set_module_index_file_name ($command->{file_name});
  } elsif ($command->{type} eq 'prepend-mirror') {
    if ($command =~ m{^[^/]}) {
      $command->{url} = abs_path $command->{url};
    }
    unshift @CPANMirror, $command->{url};
  } elsif ($command->{type} eq 'write-dep-graph') {
    write_dep_graph $dep_graph => $command->{file_name},
        format => $command->{format};
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
    delete_pmpp_arch_dir $PerlCommand, $perl_version;
  } elsif ($command->{type} eq 'print-scanned-dependency') {
    my $mod_names = scan_dependency_from_directory $command->{dir_name};
    print map { $_ . "\n" } sort { $a cmp $b } keys %$mod_names;
  } elsif ($command->{type} eq 'print-submodule-components') {
    my $list = find_install_list $RootDirName,
        recursive => 1, exclusions => $exclusions;
    print_install_list_list $list;
  } elsif ($command->{type} eq 'print-perl-core-version') {
    install_pmbp_module PMBP::Module->new_from_package ('Module::CoreList');
    require Module::CoreList;
    print Module::CoreList->first_release ($command->{module_name});
  } elsif ($command->{type} eq 'print-module-pathname') {
    my $pathname = $command->{module}->pathname;
    print $pathname if defined $pathname;
  } elsif ($command->{type} eq 'print-module-version') {
    $get_perl_version->() unless defined $perl_version;
    my $ver = get_module_version
        $PerlCommand, $perl_version, $command->{module};
    print $ver if defined $ver;
  } elsif ($command->{type} eq 'print-perl-path') {
    $get_perl_version->() unless defined $perl_version;
    print get_perl_path ($perl_version);
  } elsif ($command->{type} eq 'print') {
    print $command->{string};

  } elsif ($command->{type} eq 'install-apache') {
    install_apache_httpd $command->{value};
  } elsif ($command->{type} eq 'install-mecab') {
    install_mecab;
  } elsif ($command->{type} eq 'install-svn') {
    install_svn;
  } elsif ($command->{type} eq 'install-awscli') {
    install_awscli;

  } elsif ($command->{type} eq 'install-perl-app') {
    $get_perl_version->() unless defined $perl_version;
    install_perl_app $PerlCommand, $perl_version, $command->{url},
        name => $command->{name},
        module_index_file_name => $module_index_file_name;

  } elsif ($command->{type} eq 'help-tutorial') {
    save_pmbp_tutorial;
    install_perldoc;
    info_end;
    info_closing;
    exec_show_pmbp_tutorial;

  } else {
    info_die "Command |$command->{type}| is not defined";
  }
} # while @Command

hide_pmpp_arch_dir $PerlCommand, $perl_version
    if $pmpp_touched and defined $perl_version;
destroy;
profiler_stop 'all';
{
  my $data = profiler_data;
  info 0, (sprintf "Done: %.3f s (", $data->{all}) . (join ', ', map { sprintf '%s: %.3f s', $_, $data->{$_} } grep { $_ ne 'all' } keys %$data) . ")";
}
info_end;
info_closing;

## ------ End of main ------

package PMBP::Module;
use Carp;

my $ModulePackagePathnameMapping;
my $LoadedModuleIndexFileName;

sub set_module_index_file_name ($$) {
  my (undef, $file_name) = @_;
  return unless defined $file_name;
  return if $LoadedModuleIndexFileName->{$file_name};
  for ((main::_read_module_index $file_name)) {
    $ModulePackagePathnameMapping->{$_->[0]} = $_->[2];
  }
  $LoadedModuleIndexFileName->{$file_name} = 1;
} # set_module_index_file_name

my $PackageCompat;
BEGIN {
  $PackageCompat = {
    'GD::Image' => 'GD',
  };
}

sub new_from_package ($$) {
  return bless {package => $PackageCompat->{$_[1]} || $_[1]}, $_[0];
} # new_from_package

sub new_from_pm_file_name ($$) {
  my $m = $_[1];
  $m =~ s/\.pm$//;
  $m =~ s{[/\\]+}{::}g;
  return bless {package => $PackageCompat->{$m} || $m}, $_[0];
} # new_from_pm_file_name

sub new_from_module_arg ($$) {
  my ($class, $arg) = @_;
  if (not defined $arg) {
    croak "Module argument is not specified";
  } elsif ($arg =~ /\A([0-9A-Za-z_:]+)\z/) {
    return bless {package => $PackageCompat->{$1} || $1}, $class;
  } elsif ($arg =~ /\A([0-9A-Za-z_:]+)~([0-9A-Za-z_.-]+)\z/) {
    return bless {package => $PackageCompat->{$1} || $1,
                  version => $2}, $class;
  } elsif ($arg =~ m{\A([0-9A-Za-z_:]+)=([Hh][Tt][Tt][Pp][Ss]?://.+)\z}) {
    my $self = bless {package => $PackageCompat->{$1} || $1,
                      url => $2}, $class;
    $self->_set_distname;
    return $self;
  } elsif ($arg =~ m{\A([0-9A-Za-z_:]+)~([0-9A-Za-z_.-]+)=([Hh][Tt][Tt][Pp][Ss]?://.+)\z}) {
    my $self = bless {package => $PackageCompat->{$1} || $1,
                      version => $2, url => $3}, $class;
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
  return bless {package => $PackageCompat->{$json->{module} || ''} || $json->{module},
                version => $json->{module_version},
                distvname => $json->{distvname} || $json->{dir},
                pathname => $json->{pathname} || (defined $json->{dir} ? 'misc/' . $json->{dir} . '.tar.gz' : undef)}, $class;
} # new_from_cpanm_scandeps_json_module

sub new_from_carton_lock_entry ($$) {
  my ($class, $json) = @_;
  my $entry = bless {package => $json->{module} || $json->{target} || $json->{name},
                     version => $json->{version},
                     pathname => $json->{pathname}}, $class;
  $entry->{package} = {
    'libxml::perl' => 'XML::Perl2SAX',
    'MIME::tools' => 'MIME::Tools',
    'IO::Compress' => 'IO::Compress::Base',
    'Mail' => 'Mail::Address',
    'Gearman' => 'Gearman::Client',
    'Template::Toolkit' => 'Template',
    'Scalar-Util-Instance' => 'Scalar::Util::Instance',
  }->{$entry->{package}} || $entry->{package};
  return $entry;
} # new_from_carton_lock_entry

sub new_from_jsonalizable ($$) {
  return bless $_[1], $_[0];
} # new_from_jsonalizable

sub new_from_indexable ($$) {
  return bless {package => $PackageCompat->{$_[1]->[0] || ''} || $_[1]->[0],
                version => $_[1]->[1] eq 'undef' ? undef : $_[1]->[1],
                pathname => $_[1]->[2]}, $_[0];
} # new_from_indexable

sub _set_distname ($) {
  my $self = shift;

  if (defined $self->{url}) {
    $self->{url} =~ s{^http://wakaba\.github\.com/}{https://wakaba.github.io/};
    $self->{url} =~ s{^http://(backpan\.perl\.org)/}{https://$1/};
  }

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
  return 1 if ($self->package || '') eq 'perl';
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
  return bless {list => [map { ref $_ eq 'HASH' ? PMBP::Module->new_from_jsonalizable ($_) : $_ } @{$_[1]}]}, $_[0];
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

sub filter_modules ($$) {
  @{$_[0]->{list}} = grep &{$_[1]}, @{$_[0]->{list}};
} # filter_modules

sub filter_modules_by_exclusions ($$) {
  my $exclusions = $_[1] or return;
  $_[0]->filter_modules (sub {
    if (defined $_->package and $exclusions->{modules}->{$_->package}) {
      main::info 4, "@{[$_->package]} is excluded by $exclusions->{modules}->{$_->package}";
      0;
    } else {
      1;
    }
  });
} # filter_modules_by_exclusions

sub merge_modules {
  my ($i1, $i2) = @_;
  my $modules = {};
  my @result;
  for ($i1->to_list, (ref $i2 eq 'ARRAY' ? @$i2 : $i2->to_list)) {
    my $package = $_->package;
    if (defined $package) {
      if ($modules->{$package}) {
        my $v1 = $_->version;
        my $v2 = $modules->{$package}->version;
        if (defined $v1 and defined $v2) {
          main::install_pmbp_module (PMBP::Module->new_from_package ('version'));
          require version;
          my $ver1 = eval { version->new ($v1) };
          my $ver2 = eval { version->new ($v2) };
          if (defined $ver1 and defined $ver2 and $ver1 > $ver2) {
            $modules->{$package} = $_;
          } else {
            #
          }
        } elsif (defined $v1) {
          $modules->{$package} = $_;
        } elsif (defined $v2) {
          #
        } else {
          #
        }
      } else {
        $modules->{$package} = $_;
      }
    } else {
      push @result, $_;
    }
  }
  @{$i1->{list}} = (grep { $_ } values %$modules, @result);
} # merge_modules

sub merge_module_index {
  $_[0]->merge_modules ($_[1]);
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
  $ perl bin/pmbp.pl --help-tutorial
  $ perl bin/pmbp.pl --version

=head1 DESCRIPTION

The C<pmbp.pl> script is a tool to manage dependency for Perl
applications.  It can be possible to automate installation process of
required version of Perl and required Perl modules, in the C<local/>
directory under the application's directory (i.e. without breaking
your system and home directory).

=head1 INSTALL

Though the pmbp.pl can be placed in your favorite directory, it is
recommended to put in the "local/bin/" directory under your
application's directory, given that "local/" is not
version-controlled.

If you have the "curl" command, the following command line saves the
latest pmbp.pl script as "local/bin/pmbp.pl" under the current
directory:

  $ curl -s -S -L https://wakaba.github.io/packages/pmbp | sh

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

Specify the URL of the perlbrew installer.

=item --perlbrew-parallel-count="integer"

Specify the number of parallel processes of perlbrew (used for the
C<-j> option to the C<perlbrew>'s C<install> command).  The default
value is the value of the environment variable C<PMBP_PARALLEL_COUNT>,
or C<1>.

=back

=head2 Options for Perl modules

=over 4

=item --cpanm-url="URL"

Specify the URL of the cpanm source code.

=back

=head2 Options on system commands

Please note that "command" in this subsection means some executable in
your system and is irrelevant to the "command" kind of options to the
script.

=over 4

=item --curl-command="curl"

Specify the path to the C<curl> command used to download files from
the Internet.  If this option is not specified, the C<curl> command in
the current C<PATH> is used.

=item --wget-command="wget"

Specify the path to the C<wget> command used to download files from
the Internet.  If this option is not specified, the C<wget> command in
the current C<PATH> is used.

=item --execute-system-package-installer

If the option is specified, or if the C<TRAVIS> environment variable
is se to a true value, the required package detected by the script is
automatically installed.

Otherwise, the suggested system packages are printed to the standard
error output and the installer is not automatically invoked.

At the time of writing, C<apt-get> (for Debian and Ubuntu), C<yum>
(for Fedora and CentOS), and C<brew> (for Mac OS X with Homebrew /
Homebrew-Cask) are supported.

Please note that, on Linux, the script execute the package manager
with C<su> or C<sudo> command.  The command would ask you to input the
password if the standard input of the script is connected to tty.
Otherwise the command would fail (unless your password is the empty
string or you are the root).  Installer are executed with options to
disable any prompt.  Also note that, on Mac OS X, the platform might
show you a password or other prompt which cannot be disabled from the
script, asking for the user's input.

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

=item --git-command="path/to/git"

Specify the path to the C<git> command.  If this option is not
specified, the C<git> command in the default search path is used.

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
and C<CI> environment variables is set to a true value, the content of
the "info file" is printed to the standard error output before the
script aborts due to some error.  This option is particularly useful
if you don't have access to the info file but you does have access to
the output of the script (e.g. in some CI environment).

=back

=head2 Help options

There are two options to show descriptions of the script.  If one of
these options are specified, any other options are ignored.  The
script exits after the descriptions are printed.

=over 4

=item --help

Show usage of various options supported by the script.

=item --help-tutorial

Show tutorial documentation using the C<perldoc> command.

=item --version

Show name, author, and license of the script.

=back

Strictly speaking, C<--help-tutorial> is technically a command rather
than a normal option.  Any other command before the C<--help-tutorial>
command is invoked before showing the tutorial.  Any command after the
C<--help-tutorial> command is ignored.

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
sources, including C<Makefile.PL>, C<cpanfile>, Perl modules, and Perl
scripts within the directory and then installed.

If the application specifies the version of the Perl by
C<config/perl/version.txt>, that version of Perl is installed int o
C<local/perlbrew/perls/perl-{version}> before installation of any
module.

The command generates C<config/perl/libs.txt>, which contains the
paths to application's Perl modules (see C<--write-libs-txt> for
details on its content).

The command generates C<local/bin/perl>, C<local/bin/prove>, and
C<local/bin/perldoc>, which are corresponding to C<perl>, C<prove>,
and C<perldoc> respectively, but sets environment variable such as
C<PERL5LIB> appropriately (see also the
C<--create-perl-command-shortcut> command).  You might also want to
edit C<config/perl/pmbp-shortcuts.txt> a priori or invoke additional
C<--create-perl-command-shortcut> commands after the C<--install> for
convinience of execution of your application's boot scripts and/or
Perl-based commands provided by Perl modules, such as C<plackup> and
C<nytprofhtml>.

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
C<Cpanfile> of the application itself and some submodules.  It is
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

Download the latest version of the pmbp.pl script to
C<local/bin/pmbp.pl> in the root directory.

=item --update-pmbp-pl-staging

Download the latest C<staging>-branch version of the pmbp.pl script to
C<local/bin/pmbp.pl> in the root directory.

=item --print-pmbp-pl-etag

B<Deprecated>.  Print the HTTP C<ETag> value of the current pmbp.pl
script, if available.  This is internally used to detect newer version
of the script by the C<--update-pmbp-pl> command.  If the pmbp.pl
script is not retrieved by the C<--update-pmbp-pl> command, the script
does not know its C<ETag> and this command would print nothing.

=item --create-pmbp-makefile="path/to/Makefile"

Create a sample Makefile containing rules for installing dependency
and running test scripts using pmbp.pl infrastructure.

=item --create-bootstrap-script="path/to/template path/to/output"

Create a shell script used as a "bootstrap".  The argument to this
command is a space-separated pair of template file path and result
file path.

The template file must be a bash shell script with a special line:
C<{{INSTALL}}>, which is to be expanded to lines to install pmbp's
fundamental dependencies (e.g. Perl, curl) and to download the latest
pmbp.pl script at C<local/bin/pmbp.pl> in the current directory in
result file.

The result shell script is expected to be used as the first script
executed at the begining of an automated application build process for
a clean environment.

An example of template file:

  #!/bin/bash
  cd /myapp
  {{INSTALL}}
  ## Now we can assume there are |perl| and |local/bin/pmbp.pl|.
  perl local/bin/pmbp.pl --install-commands "make git"
  git clone https://url/of/component
  cd component && make deps

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

If the command file name you'd like to create differs from the actual
command, they can be specified by using C<=> separator.  For example:

  $ perl path/to/pmbp.pl --install \
        --create-perl-command-shortcut myapp=bin/start-myapp.sh
  $ ./myapp

... would run the C<bin/start-myapp.sh> script (Note that the script
requires the C<x> permission).  As a special case, you can specify
"perl " followed by a Perl script name as the actual command (in this
case, the Perl script don't have to be have the C<x> permission).  For
example:

  $ perl path/to/pmbp.pl --install \
        --create-perl-command-shortcut myapp=perl bin/start-myapp.pl
  $ ./myapp

... would run the C<bin/start-myapp.pl> script using the perl command
chosen by the pmbp.pl script (rather than the perl selected by the
C<PATH> environment variable or shebang in the script).

If there is already a file with the specified command file name, the
file is overridden by the newly created shortcut.

Instead of manually invoking the C<--create-perl-command-shortcut>
command, if there is C<config/perl/pmbp-shortcuts.txt>, its lines are
interpreted as arguments to the C<--create-perl-command-shortcut>
command invocations in the process of the C<--install> command.  Lines
begin with the C<#> character are considered as comment lines.  For
example:

  # config/perl/pmbp-shortcuts.txt
  perl
  local/bin/hoge=bin/hoge.pl

... will generate two shortcuts: C<perl> and C<local/bin/hoge>.

=item --create-exec-command="command-name"

Create a shell script to invoke a command with environment variables
C<PATH> and C<PERL5LIB> set to appropriate values for any locally
installed Perl and its modules under the "root" directory.

The command name can be prefixed by path
(e.g. C<hoge/fuga/command-name>).  If path is specified, the shell
script is created within that directory instead (i.e. in C<hoge/fuga>
in the example).

For example, by invoking the following command:

  $ perl path/to/pmbp.pl --install \
        --create-exec-command exec

... then an executable file C<exec> is created.
Therefore,

  $ ./exec perl bin/myapp.pl
  $ ./exec prove t/mymodule-*.t

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

=item --install-modules-by-dir-name="path/to/dir"

Install zero or more Perl modules for the specified directory.  If
there is a file "config/perl/pmb-install.txt" under the directory, it
is parsed as a "pmb install list" file and modules listed in the file
are installed.  Otherwise, required modules are examined in the same
ways as the C<--install-modules-by-list> option under the directory.

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
by L<Carton>.  Use of this command is deprecated.

=item --read-pmbp-exclusions-txt="path/to/pmbp-exclusions.txt"

Read the "pmbp exclusions text" (pmbp-exclusions.txt) file, which
contains the list of "pmb install list" components and list of Perl
modules that should be ignored.

In most cases you don't want to specify this command directly, but
commands C<--update> and C<--install> implicitly load the exclusions
list, if there is C<config/perl/pmbp-exclusions.txt> in the
application's root directory.

=item --write-module-index="path/to/packages.txt"

Write the index of known Perl modules, holded by the script, into the
specified file.

=item --write-pmb-install-list="path/to/modules.txt"

Write the "list of the selected modules" into the specified file, in
the "pmb install list" format.

=item --print-submodule-components

Print the list of recognized submodules of the application and the
application's and submodules' dependency components.

For example, consider an application which has "modules/A" and
"modules/B".  The "modules/B" contains "config/perl/modules.core.txt"
and "config/perl/modules.tests.txt".  Then, running the command:

  $ perl pmbp.pl --read-pmbp-exclusions-txt config/perl/pmbp-exclusions.txt \
        --print-submodule-components

... will show:

  modules/A
  modules/B
    core
    tests

If the application does not use "tests" component of the "modules/B"
(since it is only required by the "modules/B" to run tests of their
own), you can create the C<config/perl/pmbp-exclusions.txt>
containing:

  - "../../modules/B" tests

At this point, the first command will print:

  modules/A
  modules/B
    core
    tests    (excluded)

... and the C<--update> command will skip the "tests" component.

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

=item --write-dep-graph="path/to/file.txt"

Write a file which contains the newline-separated list of the edges of
the module dependency graph.  Each line is a tab-separated list of
source and destination nodes.  Nodes are represented as its label.

This command should be invoked after relevant modules are selected,
e.g.:

  $ perl local/bin/pmbp.pl --update --select-module Additional::Module \
        --write-dep-graph=mygraph.txt

=item --write-dep-graph-springy="path/to/file.html"

Similar to the C<--write-dep-graph> command, this command generates
the dependency graph, but as an HTML file which renders the graph
using springy.js <http://getspringy.com/>.

=back

=head2 Commands for controling cpanm behavior

=over 4

=item --set-module-index="path/to/index.txt"

Set the path to the CPAN package index, relative to the current
directory, used as input to the C<cpanm> command.

=item --prepend-mirror=URL

Prepend the specified CPAN mirror URL to the list of mirrors.

=item --print-cpan-top-url

Print the URL of the CPAN Web site used to install Perl and CPAN
modules.

=back

=head2 Installing applications

=over 4

=item --install-commands "APP1 APP2 APP3 ..."

Install executable applications, if necessary.  If some of
applications specified are not available, they are installed, using
platform's package manager or by compiling from source codes.

Zero or more applications can be specified as space-separated list of
the following names:

  curl          curl
  docker        Docker
  gcc           GCC
  g++           GNU C++ Compiler
  git           Git
  make          GNU Make
  mysql-client  MySQL (or MariaDB) client
  mysqld        MySQL (or MariaDB) server
  ssh-keygen    ssh-keygen command
  tar           tar
  vim           vim
  wget          wget

=item --install-git

=item --install-curl

=item --install-wget

=item --install-make

=item --install-gcc

=item --install-mysqld

=item --install-mysql-client

=item --install-ssh-keygen

These C<--install-NAME> commands are shorthands for
C<--install-commands NAME>.

=item --install-openssl

Install LibreSSL into C<local/common>.

=item --install-openssl-if-old

Same as C<--install-openssl> but has no effect unless an OpenSSL is
installed and it is not too old.

=item --install-openssl-if-mac

B<Deprecated>.  Same as C<--install-openssl-if-old>.

=item --print-openssl-version

Print the OpenSSL version, if installed.

=item --print-openssl-stable-branch

B<Deprecated>.  Print the GitHub branch name for the latest OpenSSL
stable version.

=item --print-libressl-stable-branch

Print the GitHub branch name for the latest LibreSSL stable version.

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

=item --install-svn

Install Apache Subversion into C<local/apache/svn>.  If subversion is
already installed, this command does nothing.

This option is no longer formally supported.

=item --install-awscli

Install AWS CLI to the system.  If it is already installed, this
command does nothing.

=item --install-perl-app="[name=]git://url/of/repo.git"

Install a Perl application.  The command argument must be a Git
repository URL, optionally preceded by a short name with the sparator
C<=>.  The name is used as part of the directory in which the
application is contained.  If it is omitted, the last path segment of
the URL, ignoring C<.git> suffix, is used.  For example:

  --install-perl-app=git://github.com/wakaba/cinnamon.git

... will install the application in the local/cinnamon directory and

  --install-perl-app=deploy=git://github.com/wakaba/cinnamon.git

... will install the application in the local/deploy directory.

The application must be either one of following forms:

=over 4

=item

It contains the C<Makefile> at the root directory of the application
such that executing C<make deps> at the directory runs any required
preparation steps, including C<git submodule update --init>,
installation of required CPAN modules, compiling of XS modules, and so
on.

=item

Otherwise, it contains the C<cpanfile> at the root directory of the
application such that executing C<carton install> at the directory
installs any required CPAN module and the application is ready to
execute.

=item

Otherwise, it contains the C<Makefile.PL> script at the root directory
of the application such that executing C<git submodule update --init;
perl Makefile.PL; make> at the directory installs any required CPAN
module and the application is ready to execute.

=back

=back

=head2 Commands for git repositories

=over 4

=item --init-git-repository

Initialize the root directory of the application as a Git repository,
using C<git init>, if it is not yet a Git repository.

=item --add-to-gitignore="path"

Add the specified file name or path to the C<.gitignore> file in the
root directory (if not yet).

=item --add-git-submodule="url"

=item --add-git-submodule="parent-path url"

Add a Git submodule.

When this command is invoked, the root directory (the path specified
by C<--root-dir-name>) must be a Git repository.

If a URL is specified, it is interpreted as a Git repository URL and
the container directory path is set to C<modules>.  If a path relative
to the root of the Git repository, followed by a space character,
followed by a URL, is specified, it is used as the container directory
path and the URL is interpreted as a Git repository URL.  Note that
there must be no trailing slash (C</>) character in the container
directory path.

If there is already a Git submodule with the specified URL as a child
of the container directory or as a child of C<modules> directory,
this command does nothing.

Otherwise, the specified Git repository is added as a child of the
container directory, whose directory name is the last path segment of
the Git repository URL, ignoring any C<perl-> prefix and C<.git>
suffix.  If there is already a file with same name, C<.n> where I<n>
is an integer is appended to the name.

For example,

  $ perl local/bin/pmbp.pl --add-git-submodule git://example/my/app1.git

... will add the Git repository as a submodule C<modules/app1>.

  $ perl local/bin/pmbp.pl --add-git-submodule "t_deps/modules git://example/my/app1.git"

... will add the Git repository as a submodule C<t_deps/modules/app1>.
(It will do nothing, however, in case that there is C<modules/app1>.)

If the submodule added contains a file
C<config/perl/pmbp-extra-modules.txt>, its content is merged into the
C<config/perl/pmbp-exclusions.txt> of the repository of the
application.  See the L</FILES> section.

=item --add-git-submodule-recursively="url"

=item --add-git-submodule-recursively="parent-path url"

Add a Git submodule recursively.  That is, this command adds the
specified Git repository, as well as submodules of the repository in
the specified container directory (if specified) or the C<modules>
directory (if not specified).

If there is already a Git submodule which is specified one or its descendant
as a child of the container directory or as a child of C<modules> directory,
that submodule will not be installed.

=back

=head2 Other command

=over 4

=item --print="string"

Print the string.  Any string can be specified as the argument.  This
command might be useful to combine multiple C<--print-*> commands.

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

=item PMBP_IGNORE_TLS_ERRORS

If specified to a true value, any TLS (SSL) certificate error in HTTPS
connection is ignored.

=item PMBP_VERBOSE

Set the default verbosity level.  See C<--verbose> option for details.

=item CI

=item TRAVIS

The C<CI> environment variable is set by various CI platforms.

The C<TRAVIS> environment variable is set by Travis CI
<https://about.travis-ci.org/docs/user/ci-environment/#Environment-variables>.

These environment variables affect log level.  Additionally, these
environment variables enable automatical installation of Debian apt
packages, if necessary.  See description for related options for more
information.

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

=head2 config/perl/pmbp-dead.txt

When the pmbp script failed to complete the requested actions, the
content of this file, if any, is printed to the standard error output.
The file can contain instructions for non-Perl-skilled members in the
application development team facing failure of the building process of
the application on their local development environment, for example.

The file is echoed as is.  Therefore the content must be encoded in
the terminal's character encoding, usually UTF-8.

Any string C<{InfoFileName}> (including enclosing braces) is replaced
by the path to the "info file" (as in C<--preserve-info-file>).

=head2 config/perl/pmbp-exclusions.txt

The "pmbp exclusions text" format has the line-based syntax with two
kinds of statements: component exclusion and module exclusion.

The component exclusion is:

  - "../../modules/mysubmodule" hoge fuga foo

... (with no leading spaces) where I<modules/mysubmodule> is path to
one of submodules of the application, relative to the exclusions file,
and I<hoge fuga foo> is a space-separated list of component names.
(Note that the line begins with a C<-> character.)  This line will
prevent these files from loaded:

  modules/mysubmodules/config/perl/modules.hoge.txt
  modules/mysubmodules/config/perl/modules.fuga.txt
  modules/mysubmodules/config/perl/modules.foo.txt

The module exclusion is:

  - MyModule::Name

... (with no leading spaces) where I<MyModule::Name> is the name of a
Perl module package.  The modules specified in this format is removed
from the list of installed modules, if any.

This file is read by the C<--update> command.  See also the
C<--read-pmbp-exclusions-txt> command.

=head2 config/perl/pmbp-extra-modules.txt

The list of extra sets of modules, which should not be required by
default when the Git repository is incorporated as a submodule.

Each line in the file can be either a module name, a comment line,
i.e. a line started by a C<#> character, or an empty line.  A module
name is a sequence of ASCII alphanumeric characters, as used in the
C<*> portion of the file name C<config/perl/modules.*.txt> as
described in the earlier section.

The file is used to append a line to the
C<config/perl/pmbp-exclusions.txt> by the C<--add-git-submodule> and
C<--add-git-submodule-recursively> commands, when the repository is
added as a submodule.  It is not used otherwise.

=head2 config/perl/pmbp-shortcuts.txt

If there is the C<config/perl/pmbp-shortcuts.txt> file, the
C<--install> command uses the content of the file to create
"shortcuts" for Perl-based commands.  See the
C<--create-perl-command-shortcut> command.

The file and the C<--create-perl-command-shortcut> command have a
minor difference: shortcuts created by the file are implicitly added
to the C<.gitignore> file.

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

=head2 local/bin/perl, local/bin/perldoc, local/bin/prove

These executable scripts are automatically generated by the
C<--install> command.  They set environment variable such as C<PATH>
and C<PERL5LIB> and then run C<perl>, C<perldoc>, or C<prove>,
respectively, so that appropriate perl executable and modules are
selected.  See C<--install> and C<--create-perl-command-shortcut> for
details.

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
It can also be shown by invoking the pmbp script with option
C<--help-tutorial>.

See the tutorial for how to install mod_perl.

=head1 AUTHOR

Wakaba <wakaba@suikawiki.org>.

=head1 ACKNOWLEDGEMENTS

Thanks to suzak and nobuoka.

=head1 LICENSE

Copyright 2012-2021 Wakaba <wakaba@suikawiki.org>.

Copyright 2012-2017 Hatena <https://www.hatena.ne.jp/company/>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
