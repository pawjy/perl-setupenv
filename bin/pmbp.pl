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
    my $module = PMBP::Module->new_from_module_arg ($_[1]);
    push @command, {type => 'install-module', module => $module};
  },
  '--scandeps=s' => sub {
    my $module = PMBP::Module->new_from_module_arg ($_[1]);
    push @command, {type => 'scandeps', module => $module};
  },
  '--select-module=s' => sub {
    my $module = PMBP::Module->new_from_module_arg ($_[1]);
    push @command, {type => 'select-module', module => $module};
  },
  '--read-module-index=s' => sub {
    push @command, {type => 'read-module-index', file_name => $_[1]};
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
  '--print-libs' => sub {
    push @command, {type => 'print-libs'};
  },
  '--set-module-index=s' => sub {
    push @command, {type => 'set-module-index', file_name => $_[1]};
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
my $installed_dir_name = $local_dir_name . '/pm';
my $log_dir_name = $temp_dir_name . '/logs';
$dists_dir_name ||= $temp_dir_name . '/pmtar';
make_path $dists_dir_name;
push @cpanm_option,
    '--mirror' => (abs_path $dists_dir_name),
    map { ('--mirror' => $_) } @cpan_mirror;
my $packages_details_file_name = $dists_dir_name . '/modules/02packages.details.txt';
my $install_json_dir_name = $dists_dir_name . '/meta';
my $deps_json_dir_name = $dists_dir_name . '/deps';

sub install_module ($;%);
sub install_support_module ($;%);
sub scandeps ($$;%);

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

sub save_url ($$) {
  mkdir_for_file $_[1];
  system "wget -O \Q$_[1]\E \Q$_[0]\E 1>&2";
  die "Failed to download <$_[0]>\n" unless -f $_[1];
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
    $path = "$dists_dir_name/authors/id/$path";
    if (not -f $path) {
      save_url $url => $path;
    }
  }
} # get_local_copy_if_necessary

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

    my @module_arg = map { $_->as_cpanm_arg ($dists_dir_name) } @$modules;
    if (grep { not m{/misc/[^/]+\.tar\.gz$} } @module_arg) {
      push @option, '--save-dists' => $dists_dir_name;
    }

    if (defined $args{module_index_file_name}) {
      push @option, '--mirror-index' => $args{module_index_file_name};
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
    while (<$cmd>) {
      info "cpanm($CPANMDepth/$redo): $_";
      
      if (/^Can\'t locate (\S+\.pm) in \@INC/) {
        push @required_cpanm, PMBP::Module->new_from_pm_file_name ($1);
      } elsif (/^Building version-\S+ \.\.\. FAIL/) {
        push @required_install,
            map { PMBP::Module->new_from_package ($_) }
            qw{ExtUtils::MakeMaker ExtUtils::ParseXS};
      } elsif (/^--> Working on (\S)+$/) {
        $current_module_name = $1;
      } elsif (/^! Installing (\S+) failed\. See (.+?) for details\.$/) {
        my $log = copy_log_file $2 => $1;
        if ($log =~ m{^make: .+?ExtUtils/xsubpp}m or
            $log =~ m{^Can\'t open perl script "ExtUtils/xsubpp"}m) {
          push @required_install,
              map { PMBP::Module->new_from_package ($_) }
              qw{ExtUtils::MakeMaker ExtUtils::ParseXS};
        }
      }
    }
    close $cmd or do {
      unless ($CPANMDepth > 100 or $redo++ > 10) {
        if (@required_cpanm and $perl_lib_dir_name ne $cpanm_dir_name) {
          local $CPANMDepth = $CPANMDepth + 1;
          for my $module (@required_cpanm) {
            install_support_module $module, %args;
          }
          redo COMMAND;
        } elsif (@required_install and $perl_lib_dir_name ne $cpanm_dir_name) {
          local $CPANMDepth = $CPANMDepth + 1;
          for my $module (@required_install) {
            if ($args->{scandeps}) {
              scandeps $args->{scandeps}->{module_index}, $module;
            } else {
              install_module $module, %args;
            }
          }
          redo COMMAND;
        }
      }
      if ($args->{ignore_errors}) {
        info "cpanm($CPANMDepth): Installing @{[join ' ', map { $_->as_short } @$modules]} failed (@{[$? >> 8]}) (Ignored)";
      } else {
        die "cpanm($CPANMDepth): Installing @{[join ' ', map { $_->as_short } @$modules]} failed (@{[$? >> 8]})\n";
      }
    };
    if ($args->{scandeps} and -f $json_temp_file->filename) {
      $result->{output_json} = load_json $json_temp_file->filename;
    }
  } # COMMAND
  return $result;
} # cpanm

sub install_module ($;%) {
  my $module = shift;
  get_local_copy_if_necessary $module;
  cpanm {perl_lib_dir_name => $installed_dir_name}, [$module], @_;
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
                      scandeps => {module_index => $module_index}}, [$module];

  my $dist = $result->{output_json}->[0]
      ? $result->{output_json}->[-1]->[0]->{pathname} : undef;

  #$json->{meta}->{provides}->{$mod}->{version} || $json->{meta}->{version} || $json->{version}

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

  if (@$result) {
    $result->[0]->[0]->merge_input_data ($module);
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

sub write_pmb_install_list ($$) {
  my ($module_index => $file_name) = @_;
  
  my $result = [];
  
  for my $module (($module_index->to_list)) {
    push @$result, [$module->package, $module->version];
  }

  info_writing "pmb-install list", $file_name;
  mkdir_for_file $file_name;
  open my $file, '>', $file_name or die "$0: $file_name: $!";
  for (@$result) {
    print $file $_->[0] . (defined $_->[1] ? '~' . $_->[1] : '') . "\n";
  }
  close $file;
} # write_pmb_install_list

sub write_install_module_index ($$) {
  my ($module_index => $file_name) = @_;
  write_module_index $module_index => $file_name;
} # write_install_module_index

sub get_lib_dir_names () {
  my @lib = grep { defined } map { abs_path $_ } map { glob $_ }
      qq{$root_dir_name/lib},
      qq{$root_dir_name/modules/*/lib},
      qq{$root_dir_name/local/submodules/*/lib},
      qq{$installed_dir_name/lib/perl5/$Config{archname}},
      qq{$installed_dir_name/lib/perl5};
  return @lib;
} # get_lib_dir_names

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
  } elsif ($command->{type} eq 'scandeps') {
    info "Scanning dependency of @{[$command->{module}->as_short]}...";
    scandeps $global_module_index, $command->{module},
        skip_if_found => 1;
  } elsif ($command->{type} eq 'select-module') {
    my $mods = load_deps $global_module_index => $command->{module};
    unless ($mods) {
      info "Scanning dependency of @{[$command->{module}->as_short]}...";
      scandeps $global_module_index, $command->{module};
      $mods = load_deps $global_module_index => $command->{module};
      die "Can't detect dependency of @{[$command->{module}->as_short]}\n" unless $mods;
    }
    $selected_module_index->add_modules ($mods);
  } elsif ($command->{type} eq 'read-module-index') {
    read_module_index $command->{file_name} => $global_module_index;
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
  } elsif ($command->{type} eq 'print-libs') {
    print join ':', (get_lib_dir_names);
  } elsif ($command->{type} eq 'set-module-index') {
    $module_index_file_name = $command->{file_name};
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
  $m =~ s{[/\\]+}{::};
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
                distvname => $json->{distvname},
                pathname => $json->{pathname}}, $class;
} # new_from_cpanm_scandeps_json_module

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
  my ($self, $dists_dir_name) = @_;
  if ($self->{url}) {
    if (defined $self->{pathname}) {
      if ($self->{pathname} =~ m{^misc/}) {
        return $dists_dir_name . '/authors/id/' . $self->{pathname};
      } else {
        return $self->{pathname};
      }
    } else {
      return $self->{url};
    }
  } else {
    return $self->{package};
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
