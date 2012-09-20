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
my $pmtar_dir_name;
my $pmpp_dir_name;
my @command;
my @cpanm_option = qw(--notest --cascade-search);
my @CPANMirror = qw(
  http://search.cpan.org/CPAN
  http://cpan.metacpan.org/
  http://backpan.perl.org/
);
my $Verbose = 0;

GetOptions (
  '--perl-command=s' => \$perl,
  '--wget-command=s' => \$wget,
  '--cpanm-url=s' => \$cpanm_url,
  '--root-dir-name=s' => \$root_dir_name,
  '--pmtar-dir-name=s' => \$pmtar_dir_name,
  '--pmpp-dir-name=s' => \$pmpp_dir_name,
  '--perl-version=s' => \$perl_version,
  '--verbose' => sub { $Verbose++ },

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
  '--print-libs' => sub {
    push @command, {type => 'print-libs'};
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
  '--print-pmtar-dir-name' => sub {
    push @command, {type => 'print-pmtar-dir-name'};
  },
  '--print-scanned-dependency=s' => sub {
    push @command, {type => 'print-scanned-dependency', dir_name => $_[1]};
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
unshift @INC, $cpanm_lib_dir_name; ## Should not use XS modules.
push @cpanm_option, '--verbose' if $Verbose > 1;
my $installed_dir_name = $local_dir_name . '/pm';
my $log_dir_name = $temp_dir_name . '/logs';
$pmtar_dir_name ||= $root_dir_name . '/deps/pmtar';
$pmpp_dir_name ||= $root_dir_name . '/deps/pmpp';
make_path $pmtar_dir_name;
make_path $pmpp_dir_name;
my $packages_details_file_name = $pmtar_dir_name . '/modules/02packages.details.txt';
my $install_json_dir_name = $pmtar_dir_name . '/meta';
my $deps_json_dir_name = $pmtar_dir_name . '/deps';

sub install_support_module ($;%);
sub scandeps ($$;%);
sub cpanm ($$;%);

sub info ($) {
  print STDERR $_[0], $_[0] =~ /\n\z/ ? "" : "\n";
} # info

sub info_writing ($$) {
  print STDERR "Writing ", $_[0], " ", File::Spec->abs2rel ($_[1]), "...\n";
} # info_writing

sub pathname2distvname ($) {
  my $path = shift;
  $path =~ s{^.+/}{};
  $path =~ s{\.tar\.gz$}{};
  return $path;
} # pathname2distvname

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

sub _save_url {
  mkdir_for_file $_[1];
  info "Downloading <$_[0]>...\n";
  system "wget -O \Q$_[1]\E \Q$_[0]\E 1>&2";
  return -f $_[1];
} # _save_url

sub save_url ($$) {
  _save_url (@_) or die "Failed to download <$_[0]>\n";
} # save_url

{
  my $json_installed;
  
  sub encode_json ($) {
    unless ($json_installed) {
      $json_installed = 1;
      install_support_module PMBP::Module->new_from_package ('JSON');
    }
    require JSON;
    return JSON->new->utf8->allow_blessed->convert_blessed->allow_nonref->pretty->canonical->encode ($_[0]);
  } # encode_json

  sub decode_json ($) {
    unless ($json_installed) {
      $json_installed = 1;
      install_support_module PMBP::Module->new_from_package ('JSON');
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

sub prepare_cpanm () {
  return if -f $cpanm;
  save_url $cpanm_url => $cpanm;
} # prepare_cpanm

our $CPANMDepth = 0;
my $cpanm_init = 0;
sub cpanm ($$;%) {
  my ($args, $modules, %args) = @_;
  my $result = {};
  prepare_cpanm;

  my $perl_lib_dir_name = $args->{perl_lib_dir_name}
      or die "No |perl_lib_dir_name| specified";

  my $redo = 0;
  COMMAND: {
    my @required_cpanm;
    my @required_install;
    my @required_install2;

    my @option = ('-I' . $cpanm_lib_dir_name, $cpanm,
                  $args->{local_option} || '-L' => $perl_lib_dir_name,
                  ($args->{skip_satisfied} ? '--skip-satisfied' : ()),
                  @cpanm_option,
                  ($args->{scandeps} ? ('--scandeps', '--format=json', '--force') : ()));

    my @module_arg = map {
      ref $_ ? $_->as_cpanm_arg ($pmtar_dir_name) : $_;
    } @$modules;
    if (grep { not m{/misc/[^/]+\.tar\.gz$} } @module_arg) {
      push @option, '--save-dists' => $pmtar_dir_name;
    }

    push @option,
        '--mirror' => (abs_path $pmtar_dir_name),
        map { ('--mirror' => $_) } @CPANMirror;

    if (defined $args{module_index_file_name}) {
      push @option, '--mirror-index' => abs_path $args{module_index_file_name};
    }

    local $ENV{LANG} = 'C';
    local $ENV{PERL_CPANM_HOME} = $cpanm_home_dir_name;
    my @cmd = ($perl, 
               @option,
               @module_arg);
    info join ' ', 'PERL_CPANM_HOME=' . $cpanm_home_dir_name, @cmd;
    my $json_temp_file = File::Temp->new;
    open my $cmd, '-|', ((join ' ', map { quotemeta } @cmd) .
                         ' 2>&1 ' .
                         ($args->{scandeps} ? ' > ' . quotemeta $json_temp_file : '') .
                         '')
        or die "Failed to execute @cmd - $!\n";
    my $current_module_name = '';
    my $failed;
    my $remove_inc;
    while (<$cmd>) {
      info "cpanm($CPANMDepth/$redo): $_" if $Verbose > 0;
      
      if (/^Can\'t locate (\S+\.pm) in \@INC/) {
        push @required_cpanm, PMBP::Module->new_from_pm_file_name ($1);
      } elsif (/^Building version-\S+ \.\.\. FAIL/) {
        push @required_install,
            map { PMBP::Module->new_from_package ($_) }
            qw{ExtUtils::MakeMaker ExtUtils::ParseXS};
      } elsif (/^--> Working on (\S)+$/) {
        $current_module_name = $1;
      } elsif (/^! (?:Installing|Configuring) (\S+) failed\. See (.+?) for details\.$/) {
        my $log = copy_log_file $2 => $1;
        if ($log =~ m{^make(?:\[[0-9]+\])?: .+?ExtUtils/xsubpp}m or
            $log =~ m{^Can\'t open perl script "ExtUtils/xsubpp"}m) {
          push @required_install,
              map { PMBP::Module->new_from_package ($_) }
              qw{ExtUtils::MakeMaker ExtUtils::ParseXS};
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
          }->{$1};
          push @required_install, PMBP::Module->new_from_package ($module_name)
              if $module_name;
        } elsif ($log =~ /^Can\'t call method "load_all_extensions" on an undefined value at inc\/Module\/Install.pm /m) {
          $remove_inc = 1;
        }
        $failed = 1;
      }
    }
    (close $cmd and not $failed) or do {
      unless ($CPANMDepth > 100 or $redo++ > 10) {
        my $redo;
        if ($remove_inc and
            @module_arg and $module_arg[0] =~ m{/} and
            -d "$module_arg[0]/inc") {
          remove_tree "$module_arg[0]/inc";
          $redo = 1;
        }
        if (@required_cpanm) {
          local $CPANMDepth = $CPANMDepth + 1;
          for my $module (@required_cpanm) {
            install_support_module $module, %args;
          }
          $redo = 1;
        } elsif (@required_install) {
          if ($perl_lib_dir_name ne $cpanm_dir_name) {
            local $CPANMDepth = $CPANMDepth + 1;
            for my $module (@required_install) {
              if ($args->{scandeps}) {
                scandeps $args->{scandeps}->{module_index}, $module, %args;
              }
              cpanm {perl_lib_dir_name => $perl_lib_dir_name}, [$module], %args
                  unless $args->{no_install};
            }
            $redo = 1 unless $args->{no_install};
          } else {
            local $CPANMDepth = $CPANMDepth + 1;
            for my $module (@required_install) {
              cpanm {perl_lib_dir_name => $perl_lib_dir_name}, [$module], %args;
            }
            $redo = 1;
          }
        }
        redo COMMAND if $redo;
      }
      if ($args->{ignore_errors}) {
        info "cpanm($CPANMDepth): Installing @{[join ' ', map { ref $_ ? $_->as_short : $_ } @$modules]} failed (@{[$? >> 8]}) (Ignored)";
      } else {
        die "cpanm($CPANMDepth): Installing @{[join ' ', map { ref $_ ? $_->as_short : $_ } @$modules]} failed (@{[$? >> 8]})\n";
      }
    }; # close or do
    if ($args->{scandeps} and -f $json_temp_file->filename) {
      $result->{output_json} = load_json $json_temp_file->filename;
    }
  } # COMMAND
  return $result;
} # cpanm

sub install_module ($;%) {
  my ($module, %args) = @_;
  get_local_copy_if_necessary $module;
  cpanm {perl_lib_dir_name => $args{pmpp} ? $pmpp_dir_name : $installed_dir_name}, [$module], %args;
} # install_module

sub install_support_module ($;%) {
  my $module = shift;
  get_local_copy_if_necessary $module;
  cpanm {perl_lib_dir_name => $cpanm_dir_name,
         local_option => '-l', skip_satisfied => 1}, [$module], @_;
} # install_support_module

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
                      scandeps => {module_index => $module_index}}, [$module],
                     %args;

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

  $result = [($convert_list->($result->{output_json} || {}))];

  if ($module) {
    for (@$result) {
      if (defined $_->[0]->{pathname} and defined $module->{pathname} and
          $_->[0]->{pathname} eq $module->{pathname}) {
        $_->[0]->merge_input_data ($module);
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
    info_writing "json file", $file_name;
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
  $module_index->add_modules ([map { $_->[0] } @$result]);
} # scandeps

sub load_deps ($$) {
  my ($module_index, $input_module) = @_;
  my $module = $module_index->find_by_module ($input_module) or return undef;

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
      info "$json_file_name not found";
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

sub select_module ($$$;%) {
  my ($src_module_index => $module => $dest_module_index, %args) = @_;
  
  my $mods = load_deps $src_module_index => $module;
  unless ($mods) {
    info "Scanning dependency of @{[$module->as_short]}...";
    scandeps $src_module_index, $module, %args;
    $mods = load_deps $src_module_index => $module;
    unless ($mods) {
      if (defined $module->pathname) {
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
          if (defined $path and $path =~ s{-[0-9A-Za-z.-]+\.tar\.gz$}{-@{[$module->version]}.tar.gz}) {
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
  $dest_module_index->add_modules ($mods);
} # select_module

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
# exit unless -f "}.$pmtar_dir_name.q{/authors/id/".$data->{pathname};
# for (keys %{$data->{provides}}) {
# $ver = $data->{provides}->{$_}->{version} || "undef";

sub read_module_index ($$) {
  my ($file_name => $module_index) = @_;
  unless (-f $file_name) {
    info "$file_name not found; skipped\n";
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
  $module_index->add_modules ($modules);
} # read_module_index

sub write_module_index ($$) {
  my ($module_index => $file_name) = @_;
  my @list;
  for my $module (($module_index->to_list)) {
    my $mod = $module->package;
    my $ver = $module->version;
    $ver = 'undef' if not defined $ver;
    push @list, sprintf "%s %s  %s\n",
        length $mod < 32 ? $mod . (" " x (32 - length $mod)) : $mod,
        length $ver < 10 ? (" " x (10 - length $ver)) . $ver : $ver,
        $module->pathname;
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
} # write_module_index

sub read_pmb_install_list ($$) {
  my ($file_name => $module_index) = @_;
  unless (-f $file_name) {
    info "$file_name not found; skipped\n";
    return;
  }
  open my $file, '<', $file_name or die "$0: $file_name: $!";
  my $modules = [];
  while (<$file>) {
    if (/^\s*\#/ or /^\*$/) {
      #
    } else {
      s/^\s+//;
      s/\s+$//;
      push @$modules, PMBP::Module->new_from_module_arg ($_);
    }
  }
  $module_index->add_modules ($modules);
} # read_pmb_install_list

sub write_pmb_install_list ($$) {
  my ($module_index => $file_name) = @_;
  
  my $result = [];
  
  for my $module (($module_index->to_list)) {
    push @$result, [$module->package, $module->version];
  }

  info_writing "pmb-install list", $file_name;
  mkdir_for_file $file_name;
  open my $file, '>', $file_name or die "$0: $file_name: $!";
  my $found = {};
  for (@$result) {
    my $v = $_->[0] . (defined $_->[1] ? '~' . $_->[1] : '');
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
  $module_index->add_modules ($modules);
} # read_carton_lock

sub read_install_list ($$);
sub read_install_list ($$) {
  my ($dir_name => $module_index) = @_;

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
      push @$modules, PMBP::Module->new_from_package ($_);
    }
    $module_index->add_modules ($modules);
    last THIS;
  } # THIS

  ## Submodules
  for my $dir_name (map { glob "$dir_name/$_" } qw(
    modules/* t_deps/modules/* local/submodules/*
  )) {
    read_install_list $dir_name => $module_index;
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
  $module_index->add_modules ($modules);
} # get_dependency_from_cpanfile

sub scan_dependency_from_directory ($) {
  my $dir_name = abs_path shift;

  my $modules = {};

  my @include_dir_name = qw(bin lib script t t_deps);
  my @exclude_pattern = map { "$dir_name/$_" } qw(modules t_deps/modules t_deps/projects);
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
  );
  for (keys %$modules) {
    delete $modules->{$_} unless /\A[0-9A-Za-z_]+(?:::[0-9A-Za-z_]+)*\z/;
  }

  return $modules;
} # scan_dependency_from_directory

sub get_lib_dir_names () {
  my @lib = grep { defined } map { abs_path $_ } map { glob $_ }
      qq{$root_dir_name/lib},
      qq{$root_dir_name/modules/*/lib},
      qq{$root_dir_name/local/submodules/*/lib},
      qq{$installed_dir_name/lib/perl5/$Config{archname}},
      qq{$installed_dir_name/lib/perl5};
  return @lib;
} # get_lib_dir_names

sub delete_pmpp_arch_dir () {
  remove_tree "$pmpp_dir_name/lib/perl5/$Config{archname}";
} # delete_pmpp_arch_dir

sub destroy_cpanm_home () {
  remove_tree $cpanm_home_dir_name;
} # destroy_cpanm_home

sub destroy () {
  destroy_cpanm_home;
} # destroy

my $global_module_index = PMBP::ModuleIndex->new_empty;
my $selected_module_index = PMBP::ModuleIndex->new_empty;
my $module_index_file_name;

for my $command (@command) {
  if ($command->{type} eq 'install-module') {
    info "Install @{[$command->{module}->as_short]}...";
    install_module $command->{module},
        module_index_file_name => $module_index_file_name;
  } elsif ($command->{type} eq 'install-modules-by-list') {
    my $module_index = PMBP::ModuleIndex->new_empty;
    if (defined $command->{file_name}) {
      read_pmb_install_list $command->{file_name} => $module_index;
    } else {
      read_install_list $root_dir_name => $module_index;
    }
    install_module $_, module_index_file_name => $module_index_file_name
        for ($module_index->to_list);
  } elsif ($command->{type} eq 'update-pmpp-by-list') {
    my $module_index = PMBP::ModuleIndex->new_empty;
    if (defined $command->{file_name}) {
      read_pmb_install_list $command->{file_name} => $module_index;
    } else {
      read_install_list $root_dir_name => $module_index;
    }
    install_module $_, module_index_file_name => $module_index_file_name, pmpp => 1
        for ($module_index->to_list);
    delete_pmpp_arch_dir;
  } elsif ($command->{type} eq 'scandeps') {
    info "Scanning dependency of @{[$command->{module}->as_short]}...";
    scandeps $global_module_index, $command->{module},
        skip_if_found => 1,
        module_index_file_name => $module_index_file_name;
  } elsif ($command->{type} eq 'select-module') {
    select_module $global_module_index => $command->{module} => $selected_module_index,
        module_index_file_name => $module_index_file_name;
  } elsif ($command->{type} eq 'select-modules-by-list') {
    my $module_index = PMBP::ModuleIndex->new_empty;
    if (defined $command->{file_name}) {
      read_pmb_install_list $command->{file_name} => $module_index;
    } else {
      read_install_list $root_dir_name => $module_index;
    }
    select_module $global_module_index => $_ => $selected_module_index,
        module_index_file_name => $module_index_file_name
        for ($module_index->to_list);
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
    open my $file, '>', $command->{file_name}
        or die "$0: $command->{file_name}: $!";
    info_writing "lib paths", $command->{file_name};
    print $file join ':', (get_lib_dir_names);
  } elsif ($command->{type} eq 'write-makefile-pl') {
    open my $file, '>', $command->{file_name}
        or die "$0: $command->{file_name}: $!";
    info_writing "dummy Makefile.PL", $command->{file_name};
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
    $module_index_file_name = $command->{file_name};
  } elsif ($command->{type} eq 'prepend-mirror') {
    if ($command =~ m{^[^/]}) {
      $command->{url} = abs_path $command->{url};
    }
    unshift @CPANMirror, $command->{url};
  } elsif ($command->{type} eq 'print-pmtar-dir-name') {
    print $pmtar_dir_name;
  } elsif ($command->{type} eq 'print-scanned-dependency') {
    my $mod_names = scan_dependency_from_directory $command->{dir_name};
    print map { $_ . "\n" } sort { $a cmp $b } keys %$mod_names;
  } elsif ($command->{type} eq 'print-perl-core-version') {
    install_support_module PMBP::Module->new_from_package ('Module::CoreList');
    require Module::CoreList;
    print Module::CoreList->first_release ($command->{module_name});
  } else {
    die "Command |$command->{type}| is not defined";
  }
}

destroy;

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
    if ($self->{url} =~ m{/authors/id/(.+\.tar\.gz)$}) {
      $self->{pathname} = $1;
    } elsif ($self->{url} =~ m{([^/]+\.tar\.gz)$}) {
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
  return $_[0]->{pathname};
} # pathname

sub distvname ($) {
  my $self = shift;
  return $self->{distvname} if defined $self->{distvname};

  if (defined $self->{pathname}) {
    return $self->{distvname} = main::pathname2distvname $self->{pathname};
  }
  return $self->{distvname} = undef;
} # distvname

sub url ($) {
  return $_[0]->{url};
} # url

sub is_equal_module ($$) {
  my ($m1, $m2) = @_;
  return 0 if not defined $m1->{package} or not defined $m2->{package};
  return 0 if $m1->{package} ne $m2->{package};
  return 0 if defined $m1->{version} and not defined $m2->{version};
  return 0 if not defined $m1->{version} and defined $m2->{version};
  return 0 if $m1->{version} ne $m2->{version};
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
  return $self->{package} . (defined $self->{version} ? '~' . $self->{version} : '');
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
  for (@{$_[0]->{list}}) {
    if ($_->is_equal_module ($_[1]) or
        (not defined $_[1]->version and $_->package eq $_[1]->package)) {
      return $_;
    }
  }
  return undef;
} # find_by_module

sub add_modules ($$) {
  push @{$_[0]->{list}}, @{$_[1]};
} # add_modules

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

=head1 LICENSE

Copyright 2012 Wakaba <w@suika.fam.cx>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
