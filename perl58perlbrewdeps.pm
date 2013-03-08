package IPC::Cmd;

use strict;

BEGIN {

    use constant IS_VMS         => $^O eq 'VMS'                       ? 1 : 0;
    use constant IS_WIN32       => $^O eq 'MSWin32'                   ? 1 : 0;
    use constant IS_WIN98       => (IS_WIN32 and !Win32::IsWinNT())   ? 1 : 0;
    use constant ALARM_CLASS    => __PACKAGE__ . '::TimeOut';
    use constant SPECIAL_CHARS  => qw[< > | &];
    use constant QUOTE          => do { IS_WIN32 ? q["] : q['] };

    use Exporter    ();
    use vars        qw[ @ISA $VERSION @EXPORT_OK $VERBOSE $DEBUG
                        $USE_IPC_RUN $USE_IPC_OPEN3 $CAN_USE_RUN_FORKED $WARN
                        $INSTANCES $ALLOW_NULL_ARGS
                    ];

    $VERSION        = '0.80';
    $VERBOSE        = 0;
    $DEBUG          = 0;
    $WARN           = 1;
    $USE_IPC_RUN    = IS_WIN32 && !IS_WIN98;
    $USE_IPC_OPEN3  = not IS_VMS;
    $ALLOW_NULL_ARGS = 0;

    $CAN_USE_RUN_FORKED = 0;
    eval {
        require POSIX; POSIX->import();
        require IPC::Open3; IPC::Open3->import();
        require IO::Select; IO::Select->import();
        require IO::Handle; IO::Handle->import();
        require FileHandle; FileHandle->import();
        require Socket; Socket->import();
        require Time::HiRes; Time::HiRes->import();
        require Win32 if IS_WIN32;
    };
    $CAN_USE_RUN_FORKED = $@ || !IS_VMS && !IS_WIN32;

    @ISA            = qw[Exporter];
    @EXPORT_OK      = qw[can_run run run_forked QUOTE];
}

require Carp;
use Socket;
use File::Spec;
use Text::ParseWords            ();             # import ONLY if needed!
#use Module::Load::Conditional   qw[can_load];
#use Locale::Maketext::Simple    Style => 'gettext';
sub loc (@) { return sprintf @_ }

=pod

=head1 NAME

IPC::Cmd - finding and running system commands made easy

=head1 SYNOPSIS

    use IPC::Cmd qw[can_run run run_forked];

    my $full_path = can_run('wget') or warn 'wget is not installed!';

    ### commands can be arrayrefs or strings ###
    my $cmd = "$full_path -b theregister.co.uk";
    my $cmd = [$full_path, '-b', 'theregister.co.uk'];

    ### in scalar context ###
    my $buffer;
    if( scalar run( command => $cmd,
                    verbose => 0,
                    buffer  => \$buffer,
                    timeout => 20 )
    ) {
        print "fetched webpage successfully: $buffer\n";
    }


    ### in list context ###
    my( $success, $error_message, $full_buf, $stdout_buf, $stderr_buf ) =
            run( command => $cmd, verbose => 0 );

    if( $success ) {
        print "this is what the command printed:\n";
        print join "", @$full_buf;
    }

    ### check for features
    print "IPC::Open3 available: "  . IPC::Cmd->can_use_ipc_open3;
    print "IPC::Run available: "    . IPC::Cmd->can_use_ipc_run;
    print "Can capture buffer: "    . IPC::Cmd->can_capture_buffer;

    ### don't have IPC::Cmd be verbose, ie don't print to stdout or
    ### stderr when running commands -- default is '0'
    $IPC::Cmd::VERBOSE = 0;


=head1 DESCRIPTION

IPC::Cmd allows you to run commands platform independently,
interactively if desired, but have them still work.

The C<can_run> function can tell you if a certain binary is installed
and if so where, whereas the C<run> function can actually execute any
of the commands you give it and give you a clear return value, as well
as adhere to your verbosity settings.

=head1 CLASS METHODS

=head2 $ipc_run_version = IPC::Cmd->can_use_ipc_run( [VERBOSE] )

Utility function that tells you if C<IPC::Run> is available.
If the C<verbose> flag is passed, it will print diagnostic messages
if L<IPC::Run> can not be found or loaded.

=cut


sub can_use_ipc_run     {
    my $self    = shift;
    my $verbose = shift || 0;

    ### IPC::Run doesn't run on win98
    return if IS_WIN98;

    ### if we dont have ipc::run, we obviously can't use it.
    return;
    #return unless can_load(
    #                    modules => { 'IPC::Run' => '0.55' },
    #                    verbose => ($WARN && $verbose),
    #                );

    ### otherwise, we're good to go
    return $IPC::Run::VERSION;
}

=head2 $ipc_open3_version = IPC::Cmd->can_use_ipc_open3( [VERBOSE] )

Utility function that tells you if C<IPC::Open3> is available.
If the verbose flag is passed, it will print diagnostic messages
if C<IPC::Open3> can not be found or loaded.

=cut


sub can_use_ipc_open3   {
    my $self    = shift;
    my $verbose = shift || 0;

    ### IPC::Open3 is not working on VMS because of a lack of fork.
    return if IS_VMS;

    ### IPC::Open3 works on every non-VMS platform platform, but it can't
    ### capture buffers on win32 :(
    return;
    #return unless can_load(
    #    modules => { map {$_ => '0.0'} qw|IPC::Open3 IO::Select Symbol| },
    #    verbose => ($WARN && $verbose),
    #);

    return $IPC::Open3::VERSION;
}

=head2 $bool = IPC::Cmd->can_capture_buffer

Utility function that tells you if C<IPC::Cmd> is capable of
capturing buffers in it's current configuration.

=cut

sub can_capture_buffer {
    my $self    = shift;

    return 1 if $USE_IPC_RUN    && $self->can_use_ipc_run;
    return 1 if $USE_IPC_OPEN3  && $self->can_use_ipc_open3;
    return;
}

=head2 $bool = IPC::Cmd->can_use_run_forked

Utility function that tells you if C<IPC::Cmd> is capable of
providing C<run_forked> on the current platform.

=head1 FUNCTIONS

=head2 $path = can_run( PROGRAM );

C<can_run> takes only one argument: the name of a binary you wish
to locate. C<can_run> works much like the unix binary C<which> or the bash
command C<type>, which scans through your path, looking for the requested
binary.

Unlike C<which> and C<type>, this function is platform independent and
will also work on, for example, Win32.

If called in a scalar context it will return the full path to the binary
you asked for if it was found, or C<undef> if it was not.

If called in a list context and the global variable C<$INSTANCES> is a true
value, it will return a list of the full paths to instances
of the binary where found in C<PATH>, or an empty list if it was not found.

=cut

sub can_run {
    my $command = shift;

    # a lot of VMS executables have a symbol defined
    # check those first
    if ( $^O eq 'VMS' ) {
        require VMS::DCLsym;
        my $syms = VMS::DCLsym->new;
        return $command if scalar $syms->getsym( uc $command );
    }

    require File::Spec;
    require ExtUtils::MakeMaker;

    my @possibles;

    if( File::Spec->file_name_is_absolute($command) ) {
        return MM->maybe_command($command);

    } else {
        for my $dir (
            File::Spec->path,
            File::Spec->curdir
        ) {
            next if ! $dir || ! -d $dir;
            my $abs = File::Spec->catfile( IS_WIN32 ? Win32::GetShortPathName( $dir ) : $dir, $command);
            push @possibles, $abs if $abs = MM->maybe_command($abs);
        }
    }
    return @possibles if wantarray and $INSTANCES;
    return shift @possibles;
}

=head2 $ok | ($ok, $err, $full_buf, $stdout_buff, $stderr_buff) = run( command => COMMAND, [verbose => BOOL, buffer => \$SCALAR, timeout => DIGIT] );

C<run> takes 4 arguments:

=over 4

=item command

This is the command to execute. It may be either a string or an array
reference.
This is a required argument.

See L<"Caveats"> for remarks on how commands are parsed and their
limitations.

=item verbose

This controls whether all output of a command should also be printed
to STDOUT/STDERR or should only be trapped in buffers (NOTE: buffers
require L<IPC::Run> to be installed, or your system able to work with
L<IPC::Open3>).

It will default to the global setting of C<$IPC::Cmd::VERBOSE>,
which by default is 0.

=item buffer

This will hold all the output of a command. It needs to be a reference
to a scalar.
Note that this will hold both the STDOUT and STDERR messages, and you
have no way of telling which is which.
If you require this distinction, run the C<run> command in list context
and inspect the individual buffers.

Of course, this requires that the underlying call supports buffers. See
the note on buffers above.

=item timeout

Sets the maximum time the command is allowed to run before aborting,
using the built-in C<alarm()> call. If the timeout is triggered, the
C<errorcode> in the return value will be set to an object of the
C<IPC::Cmd::TimeOut> class. See the L<"error message"> section below for
details.

Defaults to C<0>, meaning no timeout is set.

=back

C<run> will return a simple C<true> or C<false> when called in scalar
context.
In list context, you will be returned a list of the following items:

=over 4

=item success

A simple boolean indicating if the command executed without errors or
not.

=item error message

If the first element of the return value (C<success>) was 0, then some
error occurred. This second element is the error message the command
you requested exited with, if available. This is generally a pretty
printed value of C<$?> or C<$@>. See C<perldoc perlvar> for details on
what they can contain.
If the error was a timeout, the C<error message> will be prefixed with
the string C<IPC::Cmd::TimeOut>, the timeout class.

=item full_buffer

This is an array reference containing all the output the command
generated.
Note that buffers are only available if you have L<IPC::Run> installed,
or if your system is able to work with L<IPC::Open3> -- see below).
Otherwise, this element will be C<undef>.

=item out_buffer

This is an array reference containing all the output sent to STDOUT the
command generated. The notes from L<"full_buffer"> apply.

=item error_buffer

This is an arrayreference containing all the output sent to STDERR the
command generated. The notes from L<"full_buffer"> apply.


=back

See the L<"HOW IT WORKS"> section below to see how C<IPC::Cmd> decides
what modules or function calls to use when issuing a command.

=cut

{   my @acc = qw[ok error _fds];

    ### autogenerate accessors ###
    for my $key ( @acc ) {
        no strict 'refs';
        *{__PACKAGE__."::$key"} = sub {
            $_[0]->{$key} = $_[1] if @_ > 1;
            return $_[0]->{$key};
        }
    }
}

sub can_use_run_forked {
    return $CAN_USE_RUN_FORKED eq "1";
}

# incompatible with POSIX::SigAction
#
sub install_layered_signal {
  my ($s, $handler_code) = @_;

  my %available_signals = map {$_ => 1} keys %SIG;

  die("install_layered_signal got nonexistent signal name [$s]")
    unless defined($available_signals{$s});
  die("install_layered_signal expects coderef")
    if !ref($handler_code) || ref($handler_code) ne 'CODE';

  my $previous_handler = $SIG{$s};

  my $sig_handler = sub {
    my ($called_sig_name, @sig_param) = @_;

    # $s is a closure referring to real signal name
    # for which this handler is being installed.
    # it is used to distinguish between
    # real signal handlers and aliased signal handlers
    my $signal_name = $s;

    # $called_sig_name is a signal name which
    # was passed to this signal handler;
    # it doesn't equal $signal_name in case
    # some signal handlers in %SIG point
    # to other signal handler (CHLD and CLD,
    # ABRT and IOT)
    #
    # initial signal handler for aliased signal
    # calls some other signal handler which
    # should not execute the same handler_code again
    if ($called_sig_name eq $signal_name) {
      $handler_code->($signal_name);
    }

    # run original signal handler if any (including aliased)
    #
    if (ref($previous_handler)) {
      $previous_handler->($called_sig_name, @sig_param);
    }
  };

  $SIG{$s} = $sig_handler;
}

# give process a chance sending TERM,
# waiting for a while (2 seconds)
# and killing it with KILL
sub kill_gently {
  my ($pid, $opts) = @_;

  require POSIX;

  $opts = {} unless $opts;
  $opts->{'wait_time'} = 2 unless defined($opts->{'wait_time'});
  $opts->{'first_kill_type'} = 'just_process' unless $opts->{'first_kill_type'};
  $opts->{'final_kill_type'} = 'just_process' unless $opts->{'final_kill_type'};

  if ($opts->{'first_kill_type'} eq 'just_process') {
    kill(15, $pid);
  }
  elsif ($opts->{'first_kill_type'} eq 'process_group') {
    kill(-15, $pid);
  }

  my $child_finished = 0;
  my $wait_start_time = time();

  while (!$child_finished && $wait_start_time + $opts->{'wait_time'} > time()) {
    my $waitpid = waitpid($pid, POSIX::WNOHANG);
    if ($waitpid eq -1) {
      $child_finished = 1;
    }
    Time::HiRes::usleep(250000); # quarter of a second
  }

  if (!$child_finished) {
    if ($opts->{'final_kill_type'} eq 'just_process') {
      kill(9, $pid);
    }
    elsif ($opts->{'final_kill_type'} eq 'process_group') {
      kill(-9, $pid);
    }
  }
}

sub open3_run {
  my ($cmd, $opts) = @_;

  $opts = {} unless $opts;

  my $child_in = FileHandle->new;
  my $child_out = FileHandle->new;
  my $child_err = FileHandle->new;
  $child_out->autoflush(1);
  $child_err->autoflush(1);

  my $pid = open3($child_in, $child_out, $child_err, $cmd);

  # push my child's pid to our parent
  # so in case i am killed parent
  # could stop my child (search for
  # child_child_pid in parent code)
  if ($opts->{'parent_info'}) {
    my $ps = $opts->{'parent_info'};
    print $ps "spawned $pid\n";
  }

  if ($child_in && $child_out->opened && $opts->{'child_stdin'}) {

    # If the child process dies for any reason,
    # the next write to CHLD_IN is likely to generate
    # a SIGPIPE in the parent, which is fatal by default.
    # So you may wish to handle this signal.
    #
    # from http://perldoc.perl.org/IPC/Open3.html,
    # absolutely needed to catch piped commands errors.
    #
    local $SIG{'PIPE'} = sub { 1; };

    print $child_in $opts->{'child_stdin'};
  }
  close($child_in);

  my $child_output = {
    'out' => $child_out->fileno,
    'err' => $child_err->fileno,
    $child_out->fileno => {
      'parent_socket' => $opts->{'parent_stdout'},
      'scalar_buffer' => "",
      'child_handle' => $child_out,
      'block_size' => ($child_out->stat)[11] || 1024,
      },
    $child_err->fileno => {
      'parent_socket' => $opts->{'parent_stderr'},
      'scalar_buffer' => "",
      'child_handle' => $child_err,
      'block_size' => ($child_err->stat)[11] || 1024,
      },
    };

  my $select = IO::Select->new();
  $select->add($child_out, $child_err);

  # pass any signal to the child
  # effectively creating process
  # strongly attached to the child:
  # it will terminate only after child
  # has terminated (except for SIGKILL,
  # which is specially handled)
  foreach my $s (keys %SIG) {
    my $sig_handler;
    $sig_handler = sub {
      kill("$s", $pid);
      $SIG{$s} = $sig_handler;
    };
    $SIG{$s} = $sig_handler;
  }

  my $child_finished = 0;

  my $got_sig_child = 0;
  $SIG{'CHLD'} = sub { $got_sig_child = time(); };

  while(!$child_finished && ($child_out->opened || $child_err->opened)) {

    # parent was killed otherwise we would have got
    # the same signal as parent and process it same way
    if (getppid() eq "1") {

      # end my process group with all the children
      # (i am the process group leader, so my pid
      # equals to the process group id)
      #
      # same thing which is done
      # with $opts->{'clean_up_children'}
      # in run_forked
      #
      kill(-9, $$);

      POSIX::_exit 1;
    }

    if ($got_sig_child) {
      if (time() - $got_sig_child > 1) {
        # select->can_read doesn't return 0 after SIG_CHLD
        #
        # "On POSIX-compliant platforms, SIGCHLD is the signal
        # sent to a process when a child process terminates."
        # http://en.wikipedia.org/wiki/SIGCHLD
        #
        # nevertheless kill KILL wouldn't break anything here
        #
        kill (9, $pid);
        $child_finished = 1;
      }
    }

    Time::HiRes::usleep(1);

    foreach my $fd ($select->can_read(1/100)) {
      my $str = $child_output->{$fd->fileno};
      psSnake::die("child stream not found: $fd") unless $str;

      my $data;
      my $count = $fd->sysread($data, $str->{'block_size'});

      if ($count) {
        if ($str->{'parent_socket'}) {
          my $ph = $str->{'parent_socket'};
          print $ph $data;
        }
        else {
          $str->{'scalar_buffer'} .= $data;
        }
      }
      elsif ($count eq 0) {
        $select->remove($fd);
        $fd->close();
      }
      else {
        psSnake::die("error during sysread: " . $!);
      }
    }
  }

  my $waitpid_ret = waitpid($pid, 0);
  my $real_exit = $?;
  my $exit_value  = $real_exit >> 8;

  # since we've successfully reaped the child,
  # let our parent know about this.
  #
  if ($opts->{'parent_info'}) {
    my $ps = $opts->{'parent_info'};

    # child was killed, inform parent
    if ($real_exit & 127) {
      print $ps "$pid killed with " . ($real_exit & 127) . "\n";
    }

    print $ps "reaped $pid\n";
  }

  if ($opts->{'parent_stdout'} || $opts->{'parent_stderr'}) {
    return $exit_value;
  }
  else {
    return {
      'stdout' => $child_output->{$child_output->{'out'}}->{'scalar_buffer'},
      'stderr' => $child_output->{$child_output->{'err'}}->{'scalar_buffer'},
      'exit_code' => $exit_value,
      };
  }
}

=head2 $hashref = run_forked( COMMAND, { child_stdin => SCALAR, timeout => DIGIT, stdout_handler => CODEREF, stderr_handler => CODEREF} );

C<run_forked> is used to execute some program or a coderef,
optionally feed it with some input, get its return code
and output (both stdout and stderr into separate buffers).
In addition, it allows to terminate the program
if it takes too long to finish.

The important and distinguishing feature of run_forked
is execution timeout which at first seems to be
quite a simple task but if you think
that the program which you're spawning
might spawn some children itself (which
in their turn could do the same and so on)
it turns out to be not a simple issue.

C<run_forked> is designed to survive and
successfully terminate almost any long running task,
even a fork bomb in case your system has the resources
to survive during given timeout.

This is achieved by creating separate watchdog process
which spawns the specified program in a separate
process session and supervises it: optionally
feeds it with input, stores its exit code,
stdout and stderr, terminates it in case
it runs longer than specified.

Invocation requires the command to be executed or a coderef and optionally a hashref of options:

=over

=item C<timeout>

Specify in seconds how long to run the command before it is killed with with SIG_KILL (9),
which effectively terminates it and all of its children (direct or indirect).

=item C<child_stdin>

Specify some text that will be passed into the C<STDIN> of the executed program.

=item C<stdout_handler>

Coderef of a subroutine to call when a portion of data is received on
STDOUT from the executing program.

=item C<stderr_handler>

Coderef of a subroutine to call when a portion of data is received on
STDERR from the executing program.


=item C<discard_output>

Discards the buffering of the standard output and standard errors for return by run_forked().
With this option you have to use the std*_handlers to read what the command outputs.
Useful for commands that send a lot of output.

=item C<terminate_on_parent_sudden_death>

Enable this option if you wish all spawned processes to be killed if the initially spawned
process (the parent) is killed or dies without waiting for child processes.

=back

C<run_forked> will return a HASHREF with the following keys:

=over

=item C<exit_code>

The exit code of the executed program.

=item C<timeout>

The number of seconds the program ran for before being terminated, or 0 if no timeout occurred.

=item C<stdout>

Holds the standard output of the executed command (or empty string if
there was no STDOUT output or if C<discard_output> was used; it's always defined!)

=item C<stderr>

Holds the standard error of the executed command (or empty string if
there was no STDERR output or if C<discard_output> was used; it's always defined!)

=item C<merged>

Holds the standard output and error of the executed command merged into one stream
(or empty string if there was no output at all or if C<discard_output> was used; it's always defined!)

=item C<err_msg>

Holds some explanation in the case of an error.

=back

=cut

sub run_forked {
    ### container to store things in
    my $self = bless {}, __PACKAGE__;

    require POSIX;

    if (!can_use_run_forked()) {
        Carp::carp("run_forked is not available: $CAN_USE_RUN_FORKED");
        return;
    }

    my ($cmd, $opts) = @_;

    if (!$cmd) {
        Carp::carp("run_forked expects command to run");
        return;
    }

    $opts = {} unless $opts;
    $opts->{'timeout'} = 0 unless $opts->{'timeout'};
    $opts->{'terminate_wait_time'} = 2 unless defined($opts->{'terminate_wait_time'});

    # turned on by default
    $opts->{'clean_up_children'} = 1 unless defined($opts->{'clean_up_children'});

    # sockets to pass child stdout to parent
    my $child_stdout_socket;
    my $parent_stdout_socket;

    # sockets to pass child stderr to parent
    my $child_stderr_socket;
    my $parent_stderr_socket;

    # sockets for child -> parent internal communication
    my $child_info_socket;
    my $parent_info_socket;

    socketpair($child_stdout_socket, $parent_stdout_socket, AF_UNIX, SOCK_STREAM, PF_UNSPEC) ||
      die ("socketpair: $!");
    socketpair($child_stderr_socket, $parent_stderr_socket, AF_UNIX, SOCK_STREAM, PF_UNSPEC) ||
      die ("socketpair: $!");
    socketpair($child_info_socket, $parent_info_socket, AF_UNIX, SOCK_STREAM, PF_UNSPEC) ||
      die ("socketpair: $!");

    $child_stdout_socket->autoflush(1);
    $parent_stdout_socket->autoflush(1);
    $child_stderr_socket->autoflush(1);
    $parent_stderr_socket->autoflush(1);
    $child_info_socket->autoflush(1);
    $parent_info_socket->autoflush(1);

    my $start_time = time();

    my $pid;
    if ($pid = fork) {

      # we are a parent
      close($parent_stdout_socket);
      close($parent_stderr_socket);
      close($parent_info_socket);

      my $flags;

      # prepare sockets to read from child

      $flags = 0;
      fcntl($child_stdout_socket, POSIX::F_GETFL, $flags) || die "can't fnctl F_GETFL: $!";
      $flags |= POSIX::O_NONBLOCK;
      fcntl($child_stdout_socket, POSIX::F_SETFL, $flags) || die "can't fnctl F_SETFL: $!";

      $flags = 0;
      fcntl($child_stderr_socket, POSIX::F_GETFL, $flags) || die "can't fnctl F_GETFL: $!";
      $flags |= POSIX::O_NONBLOCK;
      fcntl($child_stderr_socket, POSIX::F_SETFL, $flags) || die "can't fnctl F_SETFL: $!";

      $flags = 0;
      fcntl($child_info_socket, POSIX::F_GETFL, $flags) || die "can't fnctl F_GETFL: $!";
      $flags |= POSIX::O_NONBLOCK;
      fcntl($child_info_socket, POSIX::F_SETFL, $flags) || die "can't fnctl F_SETFL: $!";

  #    print "child $pid started\n";

      my $child_timedout = 0;
      my $child_finished = 0;
      my $child_stdout = '';
      my $child_stderr = '';
      my $child_merged = '';
      my $child_exit_code = 0;
      my $child_killed_by_signal = 0;
      my $parent_died = 0;

      my $got_sig_child = 0;
      my $got_sig_quit = 0;
      my $orig_sig_child = $SIG{'CHLD'};

      $SIG{'CHLD'} = sub { $got_sig_child = time(); };

      if ($opts->{'terminate_on_signal'}) {
        install_layered_signal($opts->{'terminate_on_signal'}, sub { $got_sig_quit = time(); });
      }

      my $child_child_pid;

      while (!$child_finished) {
        my $now = time();

        if ($opts->{'terminate_on_parent_sudden_death'}) {
          $opts->{'runtime'}->{'last_parent_check'} = 0
            unless defined($opts->{'runtime'}->{'last_parent_check'});

          # check for parent once each five seconds
          if ($now - $opts->{'runtime'}->{'last_parent_check'} > 5) {
            if (getppid() eq "1") {
              kill_gently ($pid, {
                'first_kill_type' => 'process_group',
                'final_kill_type' => 'process_group',
                'wait_time' => $opts->{'terminate_wait_time'}
                });
              $parent_died = 1;
            }

            $opts->{'runtime'}->{'last_parent_check'} = $now;
          }
        }

        # user specified timeout
        if ($opts->{'timeout'}) {
          if ($now - $start_time > $opts->{'timeout'}) {
            kill_gently ($pid, {
              'first_kill_type' => 'process_group',
              'final_kill_type' => 'process_group',
              'wait_time' => $opts->{'terminate_wait_time'}
              });
            $child_timedout = 1;
          }
        }

        # give OS 10 seconds for correct return of waitpid,
        # kill process after that and finish wait loop;
        # shouldn't ever happen -- remove this code?
        if ($got_sig_child) {
          if ($now - $got_sig_child > 10) {
            print STDERR "waitpid did not return -1 for 10 seconds after SIG_CHLD, killing [$pid]\n";
            kill (-9, $pid);
            $child_finished = 1;
          }
        }

        if ($got_sig_quit) {
          kill_gently ($pid, {
            'first_kill_type' => 'process_group',
            'final_kill_type' => 'process_group',
            'wait_time' => $opts->{'terminate_wait_time'}
            });
          $child_finished = 1;
        }

        my $waitpid = waitpid($pid, POSIX::WNOHANG);

        # child finished, catch it's exit status
        if ($waitpid ne 0 && $waitpid ne -1) {
          $child_exit_code = $? >> 8;
        }

        if ($waitpid eq -1) {
          $child_finished = 1;
          next;
        }

        # child -> parent simple internal communication protocol
        while (my $l = <$child_info_socket>) {
          if ($l =~ /^spawned ([0-9]+?)\n(.*?)/so) {
            $child_child_pid = $1;
            $l = $2;
          }
          if ($l =~ /^reaped ([0-9]+?)\n(.*?)/so) {
            $child_child_pid = undef;
            $l = $2;
          }
          if ($l =~ /^[\d]+ killed with ([0-9]+?)\n(.*?)/so) {
            $child_killed_by_signal = $1;
            $l = $2;
          }
        }

        while (my $l = <$child_stdout_socket>) {
          if (!$opts->{'discard_output'}) {
            $child_stdout .= $l;
            $child_merged .= $l;
          }

          if ($opts->{'stdout_handler'} && ref($opts->{'stdout_handler'}) eq 'CODE') {
            $opts->{'stdout_handler'}->($l);
          }
        }
        while (my $l = <$child_stderr_socket>) {
          if (!$opts->{'discard_output'}) {
            $child_stderr .= $l;
            $child_merged .= $l;
          }
          if ($opts->{'stderr_handler'} && ref($opts->{'stderr_handler'}) eq 'CODE') {
            $opts->{'stderr_handler'}->($l);
          }
        }

        Time::HiRes::usleep(1);
      }

      # $child_pid_pid is not defined in two cases:
      #  * when our child was killed before
      #    it had chance to tell us the pid
      #    of the child it spawned. we can do
      #    nothing in this case :(
      #  * our child successfully reaped its child,
      #    we have nothing left to do in this case
      #
      # defined $child_pid_pid means child's child
      # has not died but nobody is waiting for it,
      # killing it brutally.
      #
      if ($child_child_pid) {
        kill_gently($child_child_pid);
      }

      # in case there are forks in child which
      # do not forward or process signals (TERM) correctly
      # kill whole child process group, effectively trying
      # not to return with some children or their parts still running
      #
      # to be more accurate -- we need to be sure
      # that this is process group created by our child
      # (and not some other process group with the same pgid,
      # created just after death of our child) -- fortunately
      # this might happen only when process group ids
      # are reused quickly (there are lots of processes
      # spawning new process groups for example)
      #
      if ($opts->{'clean_up_children'}) {
        kill(-9, $pid);
      }

  #    print "child $pid finished\n";

      close($child_stdout_socket);
      close($child_stderr_socket);
      close($child_info_socket);

      my $o = {
        'stdout' => $child_stdout,
        'stderr' => $child_stderr,
        'merged' => $child_merged,
        'timeout' => $child_timedout ? $opts->{'timeout'} : 0,
        'exit_code' => $child_exit_code,
        'parent_died' => $parent_died,
        'killed_by_signal' => $child_killed_by_signal,
        'child_pgid' => $pid,
        };

      my $err_msg = '';
      if ($o->{'exit_code'}) {
        $err_msg .= "exited with code [$o->{'exit_code'}]\n";
      }
      if ($o->{'timeout'}) {
        $err_msg .= "ran more than [$o->{'timeout'}] seconds\n";
      }
      if ($o->{'parent_died'}) {
        $err_msg .= "parent died\n";
      }
      if ($o->{'stdout'}) {
        $err_msg .= "stdout:\n" . $o->{'stdout'} . "\n";
      }
      if ($o->{'stderr'}) {
        $err_msg .= "stderr:\n" . $o->{'stderr'} . "\n";
      }
      if ($o->{'killed_by_signal'}) {
        $err_msg .= "killed by signal [" . $o->{'killed_by_signal'} . "]\n";
      }
      $o->{'err_msg'} = $err_msg;

      if ($orig_sig_child) {
        $SIG{'CHLD'} = $orig_sig_child;
      }
      else {
        delete($SIG{'CHLD'});
      }

      return $o;
    }
    else {
      die("cannot fork: $!") unless defined($pid);

      # create new process session for open3 call,
      # so we hopefully can kill all the subprocesses
      # which might be spawned in it (except for those
      # which do setsid theirselves -- can't do anything
      # with those)

      POSIX::setsid() || die("Error running setsid: " . $!);

      if ($opts->{'child_BEGIN'} && ref($opts->{'child_BEGIN'}) eq 'CODE') {
        $opts->{'child_BEGIN'}->();
      }

      close($child_stdout_socket);
      close($child_stderr_socket);
      close($child_info_socket);

      my $child_exit_code;

      # allow both external programs
      # and internal perl calls
      if (!ref($cmd)) {
        $child_exit_code = open3_run($cmd, {
          'parent_info' => $parent_info_socket,
          'parent_stdout' => $parent_stdout_socket,
          'parent_stderr' => $parent_stderr_socket,
          'child_stdin' => $opts->{'child_stdin'},
          });
      }
      elsif (ref($cmd) eq 'CODE') {
        $child_exit_code = $cmd->({
          'opts' => $opts,
          'parent_info' => $parent_info_socket,
          'parent_stdout' => $parent_stdout_socket,
          'parent_stderr' => $parent_stderr_socket,
          'child_stdin' => $opts->{'child_stdin'},
          });
      }
      else {
        print $parent_stderr_socket "Invalid command reference: " . ref($cmd) . "\n";
        $child_exit_code = 1;
      }

      close($parent_stdout_socket);
      close($parent_stderr_socket);
      close($parent_info_socket);

      if ($opts->{'child_END'} && ref($opts->{'child_END'}) eq 'CODE') {
        $opts->{'child_END'}->();
      }

      POSIX::_exit $child_exit_code;
    }
}

sub run {
    ### container to store things in
    my $self = bless {}, __PACKAGE__;

    my %hash = @_;

    ### if the user didn't provide a buffer, we'll store it here.
    my $def_buf = '';

    my($verbose,$cmd,$buffer,$timeout);
    my $tmpl = {
        verbose => { default  => $VERBOSE,  store => \$verbose },
        buffer  => { default  => \$def_buf, store => \$buffer },
        command => { required => 1,         store => \$cmd,
                     allow    => sub { !ref($_[0]) or ref($_[0]) eq 'ARRAY' },
        },
        timeout => { default  => 0,         store => \$timeout },
    };

    #unless( check( $tmpl, \%hash, $VERBOSE ) ) {
    #    Carp::carp( loc( "Could not validate input: %1",
    #                     Params::Check->last_error ) );
    #    return;
    #};

    $cmd = _quote_args_vms( $cmd ) if IS_VMS;

    ### strip any empty elements from $cmd if present
    if ( $ALLOW_NULL_ARGS ) {
      $cmd = [ grep { defined } @$cmd ] if ref $cmd;
    }
    else {
      $cmd = [ grep { defined && length } @$cmd ] if ref $cmd;
    }

    my $pp_cmd = (ref $cmd ? "@$cmd" : $cmd);
    print loc("Running [%1]...\n", $pp_cmd ) if $verbose;

    ### did the user pass us a buffer to fill or not? if so, set this
    ### flag so we know what is expected of us
    ### XXX this is now being ignored. in the future, we could add diagnostic
    ### messages based on this logic
    #my $user_provided_buffer = $buffer == \$def_buf ? 0 : 1;

    ### buffers that are to be captured
    my( @buffer, @buff_err, @buff_out );

    ### capture STDOUT
    my $_out_handler = sub {
        my $buf = shift;
        return unless defined $buf;

        print STDOUT $buf if $verbose;
        push @buffer,   $buf;
        push @buff_out, $buf;
    };

    ### capture STDERR
    my $_err_handler = sub {
        my $buf = shift;
        return unless defined $buf;

        print STDERR $buf if $verbose;
        push @buffer,   $buf;
        push @buff_err, $buf;
    };


    ### flag to indicate we have a buffer captured
    my $have_buffer = $self->can_capture_buffer ? 1 : 0;

    ### flag indicating if the subcall went ok
    my $ok;

    ### dont look at previous errors:
    local $?;
    local $@;
    local $!;

    ### we might be having a timeout set
    eval {
        local $SIG{ALRM} = sub { die bless sub {
            ALARM_CLASS .
            qq[: Command '$pp_cmd' aborted by alarm after $timeout seconds]
        }, ALARM_CLASS } if $timeout;
        alarm $timeout || 0;

        ### IPC::Run is first choice if $USE_IPC_RUN is set.
        if( !IS_WIN32 and $USE_IPC_RUN and $self->can_use_ipc_run( 1 ) ) {
            ### ipc::run handlers needs the command as a string or an array ref

            $self->_debug( "# Using IPC::Run. Have buffer: $have_buffer" )
                if $DEBUG;

            $ok = $self->_ipc_run( $cmd, $_out_handler, $_err_handler );

        ### since IPC::Open3 works on all platforms, and just fails on
        ### win32 for capturing buffers, do that ideally
        } elsif ( $USE_IPC_OPEN3 and $self->can_use_ipc_open3( 1 ) ) {

            $self->_debug("# Using IPC::Open3. Have buffer: $have_buffer")
                if $DEBUG;

            ### in case there are pipes in there;
            ### IPC::Open3 will call exec and exec will do the right thing

            my $method = IS_WIN32 ? '_open3_run_win32' : '_open3_run';

            $ok = $self->$method(
                                    $cmd, $_out_handler, $_err_handler, $verbose
                                );

        ### if we are allowed to run verbose, just dispatch the system command
        } else {
            $self->_debug( "# Using system(). Have buffer: $have_buffer" )
                if $DEBUG;
            $ok = $self->_system_run( $cmd, $verbose );
        }

        alarm 0;
    };

    ### restore STDIN after duping, or STDIN will be closed for
    ### this current perl process!
    $self->__reopen_fds( @{ $self->_fds} ) if $self->_fds;

    my $err;
    unless( $ok ) {
        ### alarm happened
        if ( $@ and ref $@ and $@->isa( ALARM_CLASS ) ) {
            $err = $@->();  # the error code is an expired alarm

        ### another error happened, set by the dispatchub
        } else {
            $err = $self->error;
        }
    }

    ### fill the buffer;
    $$buffer = join '', @buffer if @buffer;

    ### return a list of flags and buffers (if available) in list
    ### context, or just a simple 'ok' in scalar
    return wantarray
                ? $have_buffer
                    ? ($ok, $err, \@buffer, \@buff_out, \@buff_err)
                    : ($ok, $err )
                : $ok


}

sub _open3_run_win32 {
  my $self    = shift;
  my $cmd     = shift;
  my $outhand = shift;
  my $errhand = shift;

  my $pipe = sub {
    socketpair($_[0], $_[1], AF_UNIX, SOCK_STREAM, PF_UNSPEC)
        or return undef;
    shutdown($_[0], 1);  # No more writing for reader
    shutdown($_[1], 0);  # No more reading for writer
    return 1;
  };

  my $open3 = sub {
    local (*TO_CHLD_R,     *TO_CHLD_W);
    local (*FR_CHLD_R,     *FR_CHLD_W);
    local (*FR_CHLD_ERR_R, *FR_CHLD_ERR_W);

    $pipe->(*TO_CHLD_R,     *TO_CHLD_W    ) or die $^E;
    $pipe->(*FR_CHLD_R,     *FR_CHLD_W    ) or die $^E;
    $pipe->(*FR_CHLD_ERR_R, *FR_CHLD_ERR_W) or die $^E;

    my $pid = IPC::Open3::open3('>&TO_CHLD_R', '<&FR_CHLD_W', '<&FR_CHLD_ERR_W', @_);

    return ( $pid, *TO_CHLD_W, *FR_CHLD_R, *FR_CHLD_ERR_R );
  };

  $cmd = [ grep { defined && length } @$cmd ] if ref $cmd;
  $cmd = $self->__fix_cmd_whitespace_and_special_chars( $cmd );

  my ($pid, $to_chld, $fr_chld, $fr_chld_err) =
    $open3->( ( ref $cmd ? @$cmd : $cmd ) );

  my $in_sel  = IO::Select->new();
  my $out_sel = IO::Select->new();

  my %objs;

  $objs{ fileno( $fr_chld ) } = $outhand;
  $objs{ fileno( $fr_chld_err ) } = $errhand;
  $in_sel->add( $fr_chld );
  $in_sel->add( $fr_chld_err );

  close($to_chld);

  while ($in_sel->count() + $out_sel->count()) {
    my ($ins, $outs) = IO::Select::select($in_sel, $out_sel, undef);

    for my $fh (@$ins) {
        my $obj = $objs{ fileno($fh) };
        my $buf;
        my $bytes_read = sysread($fh, $buf, 64*1024 ); #, length($buf));
        if (!$bytes_read) {
            $in_sel->remove($fh);
        }
        else {
	          $obj->( "$buf" );
	      }
      }

      for my $fh (@$outs) {
      }
  }

  waitpid($pid, 0);

  ### some error occurred
  if( $? ) {
        $self->error( $self->_pp_child_error( $cmd, $? ) );
        $self->ok( 0 );
        return;
  } else {
        return $self->ok( 1 );
  }
}

sub _open3_run {
    my $self            = shift;
    my $cmd             = shift;
    my $_out_handler    = shift;
    my $_err_handler    = shift;
    my $verbose         = shift || 0;

    ### Following code are adapted from Friar 'abstracts' in the
    ### Perl Monastery (http://www.perlmonks.org/index.pl?node_id=151886).
    ### XXX that code didn't work.
    ### we now use the following code, thanks to theorbtwo

    ### define them beforehand, so we always have defined FH's
    ### to read from.
    use Symbol;
    my $kidout      = Symbol::gensym();
    my $kiderror    = Symbol::gensym();

    ### Dup the filehandle so we can pass 'our' STDIN to the
    ### child process. This stops us from having to pump input
    ### from ourselves to the childprocess. However, we will need
    ### to revive the FH afterwards, as IPC::Open3 closes it.
    ### We'll do the same for STDOUT and STDERR. It works without
    ### duping them on non-unix derivatives, but not on win32.
    my @fds_to_dup = ( IS_WIN32 && !$verbose
                            ? qw[STDIN STDOUT STDERR]
                            : qw[STDIN]
                        );
    $self->_fds( \@fds_to_dup );
    $self->__dup_fds( @fds_to_dup );

    ### pipes have to come in a quoted string, and that clashes with
    ### whitespace. This sub fixes up such commands so they run properly
    $cmd = $self->__fix_cmd_whitespace_and_special_chars( $cmd );

    ### dont stringify @$cmd, so spaces in filenames/paths are
    ### treated properly
    my $pid = eval {
        IPC::Open3::open3(
                    '<&STDIN',
                    (IS_WIN32 ? '>&STDOUT' : $kidout),
                    (IS_WIN32 ? '>&STDERR' : $kiderror),
                    ( ref $cmd ? @$cmd : $cmd ),
                );
    };

    ### open3 error occurred
    if( $@ and $@ =~ /^open3:/ ) {
        $self->ok( 0 );
        $self->error( $@ );
        return;
    };

    ### use OUR stdin, not $kidin. Somehow,
    ### we never get the input.. so jump through
    ### some hoops to do it :(
    my $selector = IO::Select->new(
                        (IS_WIN32 ? \*STDERR : $kiderror),
                        \*STDIN,
                        (IS_WIN32 ? \*STDOUT : $kidout)
                    );

    STDOUT->autoflush(1);   STDERR->autoflush(1);   STDIN->autoflush(1);
    $kidout->autoflush(1)   if UNIVERSAL::can($kidout,   'autoflush');
    $kiderror->autoflush(1) if UNIVERSAL::can($kiderror, 'autoflush');

    ### add an explicit break statement
    ### code courtesy of theorbtwo from #london.pm
    my $stdout_done = 0;
    my $stderr_done = 0;
    OUTER: while ( my @ready = $selector->can_read ) {

        for my $h ( @ready ) {
            my $buf;

            ### $len is the amount of bytes read
            my $len = sysread( $h, $buf, 4096 );    # try to read 4096 bytes

            ### see perldoc -f sysread: it returns undef on error,
            ### so bail out.
            if( not defined $len ) {
                warn(loc("Error reading from process: %1", $!));
                last OUTER;
            }

            ### check for $len. it may be 0, at which point we're
            ### done reading, so don't try to process it.
            ### if we would print anyway, we'd provide bogus information
            $_out_handler->( "$buf" ) if $len && $h == $kidout;
            $_err_handler->( "$buf" ) if $len && $h == $kiderror;

            ### Wait till child process is done printing to both
            ### stdout and stderr.
            $stdout_done = 1 if $h == $kidout   and $len == 0;
            $stderr_done = 1 if $h == $kiderror and $len == 0;
            last OUTER if ($stdout_done && $stderr_done);
        }
    }

    waitpid $pid, 0; # wait for it to die

    ### restore STDIN after duping, or STDIN will be closed for
    ### this current perl process!
    ### done in the parent call now
    # $self->__reopen_fds( @fds_to_dup );

    ### some error occurred
    if( $? ) {
        $self->error( $self->_pp_child_error( $cmd, $? ) );
        $self->ok( 0 );
        return;
    } else {
        return $self->ok( 1 );
    }
}

### Text::ParseWords::shellwords() uses unix semantics. that will break
### on win32
{   my $parse_sub = IS_WIN32
                        ? __PACKAGE__->can('_split_like_shell_win32')
                        : Text::ParseWords->can('shellwords');

    sub _ipc_run {
        my $self            = shift;
        my $cmd             = shift;
        my $_out_handler    = shift;
        my $_err_handler    = shift;

        STDOUT->autoflush(1); STDERR->autoflush(1);

        ### a command like:
        # [
        #     '/usr/bin/gzip',
        #     '-cdf',
        #     '/Users/kane/sources/p4/other/archive-extract/t/src/x.tgz',
        #     '|',
        #     '/usr/bin/tar',
        #     '-tf -'
        # ]
        ### needs to become:
        # [
        #     ['/usr/bin/gzip', '-cdf',
        #       '/Users/kane/sources/p4/other/archive-extract/t/src/x.tgz']
        #     '|',
        #     ['/usr/bin/tar', '-tf -']
        # ]


        my @command;
        my $special_chars;

        my $re = do { my $x = join '', SPECIAL_CHARS; qr/([$x])/ };
        if( ref $cmd ) {
            my $aref = [];
            for my $item (@$cmd) {
                if( $item =~ $re ) {
                    push @command, $aref, $item;
                    $aref = [];
                    $special_chars .= $1;
                } else {
                    push @$aref, $item;
                }
            }
            push @command, $aref;
        } else {
            @command = map { if( $_ =~ $re ) {
                                $special_chars .= $1; $_;
                             } else {
#                                [ split /\s+/ ]
                                 [ map { m/[ ]/ ? qq{'$_'} : $_ } $parse_sub->($_) ]
                             }
                        } split( /\s*$re\s*/, $cmd );
        }

        ### if there's a pipe in the command, *STDIN needs to
        ### be inserted *BEFORE* the pipe, to work on win32
        ### this also works on *nix, so we should do it when possible
        ### this should *also* work on multiple pipes in the command
        ### if there's no pipe in the command, append STDIN to the back
        ### of the command instead.
        ### XXX seems IPC::Run works it out for itself if you just
        ### dont pass STDIN at all.
        #     if( $special_chars and $special_chars =~ /\|/ ) {
        #         ### only add STDIN the first time..
        #         my $i;
        #         @command = map { ($_ eq '|' && not $i++)
        #                             ? ( \*STDIN, $_ )
        #                             : $_
        #                         } @command;
        #     } else {
        #         push @command, \*STDIN;
        #     }

        # \*STDIN is already included in the @command, see a few lines up
        my $ok = eval { IPC::Run::run(   @command,
                                fileno(STDOUT).'>',
                                $_out_handler,
                                fileno(STDERR).'>',
                                $_err_handler
                            )
                        };

        ### all is well
        if( $ok ) {
            return $self->ok( $ok );

        ### some error occurred
        } else {
            $self->ok( 0 );

            ### if the eval fails due to an exception, deal with it
            ### unless it's an alarm
            if( $@ and not UNIVERSAL::isa( $@, ALARM_CLASS ) ) {
                $self->error( $@ );

            ### if it *is* an alarm, propagate
            } elsif( $@ ) {
                die $@;

            ### some error in the sub command
            } else {
                $self->error( $self->_pp_child_error( $cmd, $? ) );
            }

            return;
        }
    }
}

sub _system_run {
    my $self    = shift;
    my $cmd     = shift;
    my $verbose = shift || 0;

    ### pipes have to come in a quoted string, and that clashes with
    ### whitespace. This sub fixes up such commands so they run properly
    $cmd = $self->__fix_cmd_whitespace_and_special_chars( $cmd );

    my @fds_to_dup = $verbose ? () : qw[STDOUT STDERR];
    $self->_fds( \@fds_to_dup );
    $self->__dup_fds( @fds_to_dup );

    ### system returns 'true' on failure -- the exit code of the cmd
    $self->ok( 1 );
    system( ref $cmd ? @$cmd : $cmd ) == 0 or do {
        $self->error( $self->_pp_child_error( $cmd, $? ) );
        $self->ok( 0 );
    };

    ### done in the parent call now
    #$self->__reopen_fds( @fds_to_dup );

    return unless $self->ok;
    return $self->ok;
}

{   my %sc_lookup = map { $_ => $_ } SPECIAL_CHARS;


    sub __fix_cmd_whitespace_and_special_chars {
        my $self = shift;
        my $cmd  = shift;

        ### command has a special char in it
        if( ref $cmd and grep { $sc_lookup{$_} } @$cmd ) {

            ### since we have special chars, we have to quote white space
            ### this *may* conflict with the parsing :(
            my $fixed;
            my @cmd = map { / / ? do { $fixed++; QUOTE.$_.QUOTE } : $_ } @$cmd;

            $self->_debug( "# Quoted $fixed arguments containing whitespace" )
                    if $DEBUG && $fixed;

            ### stringify it, so the special char isn't escaped as argument
            ### to the program
            $cmd = join ' ', @cmd;
        }

        return $cmd;
    }
}

### Command-line arguments (but not the command itself) must be quoted
### to ensure case preservation. Borrowed from Module::Build with adaptations.
### Patch for this supplied by Craig Berry, see RT #46288: [PATCH] Add argument
### quoting for run() on VMS
sub _quote_args_vms {
  ### Returns a command string with proper quoting so that the subprocess
  ### sees this same list of args, or if we get a single arg that is an
  ### array reference, quote the elements of it (except for the first)
  ### and return the reference.
  my @args = @_;
  my $got_arrayref = (scalar(@args) == 1
                      && UNIVERSAL::isa($args[0], 'ARRAY'))
                   ? 1
                   : 0;

  @args = split(/\s+/, $args[0]) unless $got_arrayref || scalar(@args) > 1;

  my $cmd = $got_arrayref ? shift @{$args[0]} : shift @args;

  ### Do not quote qualifiers that begin with '/' or previously quoted args.
  map { if (/^[^\/\"]/) {
          $_ =~ s/\"/""/g;     # escape C<"> by doubling
          $_ = q(").$_.q(");
        }
  }
    ($got_arrayref ? @{$args[0]}
                   : @args
    );

  $got_arrayref ? unshift(@{$args[0]}, $cmd) : unshift(@args, $cmd);

  return $got_arrayref ? $args[0]
                       : join(' ', @args);
}


### XXX this is cribbed STRAIGHT from M::B 0.30 here:
### http://search.cpan.org/src/KWILLIAMS/Module-Build-0.30/lib/Module/Build/Platform/Windows.pm:split_like_shell
### XXX this *should* be integrated into text::parsewords
sub _split_like_shell_win32 {
  # As it turns out, Windows command-parsing is very different from
  # Unix command-parsing.  Double-quotes mean different things,
  # backslashes don't necessarily mean escapes, and so on.  So we
  # can't use Text::ParseWords::shellwords() to break a command string
  # into words.  The algorithm below was bashed out by Randy and Ken
  # (mostly Randy), and there are a lot of regression tests, so we
  # should feel free to adjust if desired.

  local $_ = shift;

  my @argv;
  return @argv unless defined() && length();

  my $arg = '';
  my( $i, $quote_mode ) = ( 0, 0 );

  while ( $i < length() ) {

    my $ch      = substr( $_, $i  , 1 );
    my $next_ch = substr( $_, $i+1, 1 );

    if ( $ch eq '\\' && $next_ch eq '"' ) {
      $arg .= '"';
      $i++;
    } elsif ( $ch eq '\\' && $next_ch eq '\\' ) {
      $arg .= '\\';
      $i++;
    } elsif ( $ch eq '"' && $next_ch eq '"' && $quote_mode ) {
      $quote_mode = !$quote_mode;
      $arg .= '"';
      $i++;
    } elsif ( $ch eq '"' && $next_ch eq '"' && !$quote_mode &&
          ( $i + 2 == length()  ||
        substr( $_, $i + 2, 1 ) eq ' ' )
        ) { # for cases like: a"" => [ 'a' ]
      push( @argv, $arg );
      $arg = '';
      $i += 2;
    } elsif ( $ch eq '"' ) {
      $quote_mode = !$quote_mode;
    } elsif ( $ch eq ' ' && !$quote_mode ) {
      push( @argv, $arg ) if defined( $arg ) && length( $arg );
      $arg = '';
      ++$i while substr( $_, $i + 1, 1 ) eq ' ';
    } else {
      $arg .= $ch;
    }

    $i++;
  }

  push( @argv, $arg ) if defined( $arg ) && length( $arg );
  return @argv;
}



{   use File::Spec;
    use Symbol;

    my %Map = (
        STDOUT => [qw|>&|, \*STDOUT, Symbol::gensym() ],
        STDERR => [qw|>&|, \*STDERR, Symbol::gensym() ],
        STDIN  => [qw|<&|, \*STDIN,  Symbol::gensym() ],
    );

    ### dups FDs and stores them in a cache
    sub __dup_fds {
        my $self    = shift;
        my @fds     = @_;

        __PACKAGE__->_debug( "# Closing the following fds: @fds" ) if $DEBUG;

        for my $name ( @fds ) {
            my($redir, $fh, $glob) = @{$Map{$name}} or (
                Carp::carp(loc("No such FD: '%1'", $name)), next );

            ### MUST use the 2-arg version of open for dup'ing for
            ### 5.6.x compatibility. 5.8.x can use 3-arg open
            ### see perldoc5.6.2 -f open for details
            open $glob, $redir . fileno($fh) or (
                        Carp::carp(loc("Could not dup '$name': %1", $!)),
                        return
                    );

            ### we should re-open this filehandle right now, not
            ### just dup it
            ### Use 2-arg version of open, as 5.5.x doesn't support
            ### 3-arg version =/
            if( $redir eq '>&' ) {
                open( $fh, '>' . File::Spec->devnull ) or (
                    Carp::carp(loc("Could not reopen '$name': %1", $!)),
                    return
                );
            }
        }

        return 1;
    }

    ### reopens FDs from the cache
    sub __reopen_fds {
        my $self    = shift;
        my @fds     = @_;

        __PACKAGE__->_debug( "# Reopening the following fds: @fds" ) if $DEBUG;

        for my $name ( @fds ) {
            my($redir, $fh, $glob) = @{$Map{$name}} or (
                Carp::carp(loc("No such FD: '%1'", $name)), next );

            ### MUST use the 2-arg version of open for dup'ing for
            ### 5.6.x compatibility. 5.8.x can use 3-arg open
            ### see perldoc5.6.2 -f open for details
            open( $fh, $redir . fileno($glob) ) or (
                    Carp::carp(loc("Could not restore '$name': %1", $!)),
                    return
                );

            ### close this FD, we're not using it anymore
            close $glob;
        }
        return 1;

    }
}

sub _debug {
    my $self    = shift;
    my $msg     = shift or return;
    my $level   = shift || 0;

    local $Carp::CarpLevel += $level;
    Carp::carp($msg);

    return 1;
}

sub _pp_child_error {
    my $self    = shift;
    my $cmd     = shift or return;
    my $ce      = shift or return;
    my $pp_cmd  = ref $cmd ? "@$cmd" : $cmd;


    my $str;
    if( $ce == -1 ) {
        ### Include $! in the error message, so that the user can
        ### see 'No such file or directory' versus 'Permission denied'
        ### versus 'Cannot fork' or whatever the cause was.
        $str = "Failed to execute '$pp_cmd': $!";

    } elsif ( $ce & 127 ) {
        ### some signal
        $str = loc( "'%1' died with signal %d, %s coredump\n",
               $pp_cmd, ($ce & 127), ($ce & 128) ? 'with' : 'without');

    } else {
        ### Otherwise, the command run but gave error status.
        $str = "'$pp_cmd' exited with value " . ($ce >> 8);
    }

    $self->_debug( "# Child error '$ce' translated to: $str" ) if $DEBUG;

    return $str;
}

1;

=head2 $q = QUOTE

Returns the character used for quoting strings on this platform. This is
usually a C<'> (single quote) on most systems, but some systems use different
quotes. For example, C<Win32> uses C<"> (double quote).

You can use it as follows:

  use IPC::Cmd qw[run QUOTE];
  my $cmd = q[echo ] . QUOTE . q[foo bar] . QUOTE;

This makes sure that C<foo bar> is treated as a string, rather than two
separate arguments to the C<echo> function.

__END__

=head1 HOW IT WORKS

C<run> will try to execute your command using the following logic:

=over 4

=item *

If you have C<IPC::Run> installed, and the variable C<$IPC::Cmd::USE_IPC_RUN>
is set to true (See the L<"Global Variables"> section) use that to execute
the command. You will have the full output available in buffers, interactive commands
are sure to work  and you are guaranteed to have your verbosity
settings honored cleanly.

=item *

Otherwise, if the variable C<$IPC::Cmd::USE_IPC_OPEN3> is set to true
(See the L<"Global Variables"> section), try to execute the command using
L<IPC::Open3>. Buffers will be available on all platforms,
interactive commands will still execute cleanly, and also your verbosity
settings will be adhered to nicely;

=item *

Otherwise, if you have the C<verbose> argument set to true, we fall back
to a simple C<system()> call. We cannot capture any buffers, but
interactive commands will still work.

=item *

Otherwise we will try and temporarily redirect STDERR and STDOUT, do a
C<system()> call with your command and then re-open STDERR and STDOUT.
This is the method of last resort and will still allow you to execute
your commands cleanly. However, no buffers will be available.

=back

=head1 Global Variables

The behaviour of IPC::Cmd can be altered by changing the following
global variables:

=head2 $IPC::Cmd::VERBOSE

This controls whether IPC::Cmd will print any output from the
commands to the screen or not. The default is 0.

=head2 $IPC::Cmd::USE_IPC_RUN

This variable controls whether IPC::Cmd will try to use L<IPC::Run>
when available and suitable.

=head2 $IPC::Cmd::USE_IPC_OPEN3

This variable controls whether IPC::Cmd will try to use L<IPC::Open3>
when available and suitable. Defaults to true.

=head2 $IPC::Cmd::WARN

This variable controls whether run-time warnings should be issued, like
the failure to load an C<IPC::*> module you explicitly requested.

Defaults to true. Turn this off at your own risk.

=head2 $IPC::Cmd::INSTANCES

This variable controls whether C<can_run> will return all instances of
the binary it finds in the C<PATH> when called in a list context.

Defaults to false, set to true to enable the described behaviour.

=head2 $IPC::Cmd::ALLOW_NULL_ARGS

This variable controls whether C<run> will remove any empty/null arguments
it finds in command arguments.

Defaults to false, so it will remove null arguments. Set to true to allow
them.

=head1 Caveats

=over 4

=item Whitespace and IPC::Open3 / system()

When using C<IPC::Open3> or C<system>, if you provide a string as the
C<command> argument, it is assumed to be appropriately escaped. You can
use the C<QUOTE> constant to use as a portable quote character (see above).
However, if you provide an array reference, special rules apply:

If your command contains B<special characters> (< > | &), it will
be internally stringified before executing the command, to avoid that these
special characters are escaped and passed as arguments instead of retaining
their special meaning.

However, if the command contained arguments that contained whitespace,
stringifying the command would lose the significance of the whitespace.
Therefore, C<IPC::Cmd> will quote any arguments containing whitespace in your
command if the command is passed as an arrayref and contains special characters.

=item Whitespace and IPC::Run

When using C<IPC::Run>, if you provide a string as the C<command> argument,
the string will be split on whitespace to determine the individual elements
of your command. Although this will usually just Do What You Mean, it may
break if you have files or commands with whitespace in them.

If you do not wish this to happen, you should provide an array
reference, where all parts of your command are already separated out.
Note however, if there are extra or spurious whitespaces in these parts,
the parser or underlying code may not interpret it correctly, and
cause an error.

Example:
The following code

    gzip -cdf foo.tar.gz | tar -xf -

should either be passed as

    "gzip -cdf foo.tar.gz | tar -xf -"

or as

    ['gzip', '-cdf', 'foo.tar.gz', '|', 'tar', '-xf', '-']

But take care not to pass it as, for example

    ['gzip -cdf foo.tar.gz', '|', 'tar -xf -']

Since this will lead to issues as described above.


=item IO Redirect

Currently it is too complicated to parse your command for IO
redirections. For capturing STDOUT or STDERR there is a work around
however, since you can just inspect your buffers for the contents.

=item Interleaving STDOUT/STDERR

Neither IPC::Run nor IPC::Open3 can interleave STDOUT and STDERR. For short
bursts of output from a program, e.g. this sample,

    for ( 1..4 ) {
        $_ % 2 ? print STDOUT $_ : print STDERR $_;
    }

IPC::[Run|Open3] will first read all of STDOUT, then all of STDERR, meaning
the output looks like '13' on STDOUT and '24' on STDERR, instead of

    1
    2
    3
    4

This has been recorded in L<rt.cpan.org> as bug #37532: Unable to interleave
STDOUT and STDERR.

=back

=head1 See Also

L<IPC::Run>, L<IPC::Open3>

=head1 ACKNOWLEDGEMENTS

Thanks to James Mastros and Martijn van der Streek for their
help in getting L<IPC::Open3> to behave nicely.

Thanks to Petya Kohts for the C<run_forked> code.

=head1 BUG REPORTS

Please report bugs or other issues to E<lt>bug-ipc-cmd@rt.cpan.orgE<gt>.

=head1 AUTHOR

Original author: Jos Boumans E<lt>kane@cpan.orgE<gt>.
Current maintainer: Chris Williams E<lt>bingos@cpan.orgE<gt>.

=head1 COPYRIGHT

This library is free software; you may redistribute and/or modify it
under the same terms as Perl itself.

=cut
package Module::Pluggable;

use strict;
use vars qw($VERSION $FORCE_SEARCH_ALL_PATHS);
use Module::Pluggable::Object;

use if $] > 5.017, 'deprecate';

# ObQuote:
# Bob Porter: Looks like you've been missing a lot of work lately. 
# Peter Gibbons: I wouldn't say I've been missing it, Bob! 


$VERSION = '4.7';
$FORCE_SEARCH_ALL_PATHS = 0;

sub import {
    my $class        = shift;
    my %opts         = @_;

    my ($pkg, $file) = caller; 
    # the default name for the method is 'plugins'
    my $sub          = $opts{'sub_name'}  || 'plugins';
    # get our package 
    my ($package)    = $opts{'package'} || $pkg;
    $opts{filename}  = $file;
    $opts{package}   = $package;
    $opts{force_search_all_paths} = $FORCE_SEARCH_ALL_PATHS unless exists $opts{force_search_all_paths};


    my $finder       = Module::Pluggable::Object->new(%opts);
    my $subroutine   = sub { my $self = shift; return $finder->plugins(@_) };

    my $searchsub = sub {
              my $self = shift;
              my ($action,@paths) = @_;

              $finder->{'search_path'} = ["${package}::Plugin"] if ($action eq 'add'  and not   $finder->{'search_path'} );
              push @{$finder->{'search_path'}}, @paths      if ($action eq 'add');
              $finder->{'search_path'}       = \@paths      if ($action eq 'new');
              return $finder->{'search_path'};
    };


    my $onlysub = sub {
        my ($self, $only) = @_;

        if (defined $only) {
            $finder->{'only'} = $only;
        };
        
        return $finder->{'only'};
    };

    my $exceptsub = sub {
        my ($self, $except) = @_;

        if (defined $except) {
            $finder->{'except'} = $except;
        };
        
        return $finder->{'except'};
    };


    no strict 'refs';
    no warnings qw(redefine prototype);
    
    *{"$package\::$sub"}        = $subroutine;
    *{"$package\::search_path"} = $searchsub;
    *{"$package\::only"}        = $onlysub;
    *{"$package\::except"}      = $exceptsub;

}

1;

=pod

=head1 NAME

Module::Pluggable - automatically give your module the ability to have plugins

=head1 SYNOPSIS


Simple use Module::Pluggable -

    package MyClass;
    use Module::Pluggable;
    

and then later ...

    use MyClass;
    my $mc = MyClass->new();
    # returns the names of all plugins installed under MyClass::Plugin::*
    my @plugins = $mc->plugins(); 

=head1 EXAMPLE

Why would you want to do this? Say you have something that wants to pass an
object to a number of different plugins in turn. For example you may 
want to extract meta-data from every email you get sent and do something
with it. Plugins make sense here because then you can keep adding new 
meta data parsers and all the logic and docs for each one will be 
self contained and new handlers are easy to add without changing the 
core code. For that, you might do something like ...

    package Email::Examiner;

    use strict;
    use Email::Simple;
    use Module::Pluggable require => 1;

    sub handle_email {
        my $self  = shift;
        my $email = shift;

        foreach my $plugin ($self->plugins) {
            $plugin->examine($email);
        }

        return 1;
    }



.. and all the plugins will get a chance in turn to look at it.

This can be trivally extended so that plugins could save the email
somewhere and then no other plugin should try and do that. 
Simply have it so that the C<examine> method returns C<1> if 
it has saved the email somewhere. You might also wnat to be paranoid
and check to see if the plugin has an C<examine> method.

        foreach my $plugin ($self->plugins) {
            next unless $plugin->can('examine');
            last if     $plugin->examine($email);
        }


And so on. The sky's the limit.


=head1 DESCRIPTION

Provides a simple but, hopefully, extensible way of having 'plugins' for 
your module. Obviously this isn't going to be the be all and end all of
solutions but it works for me.

Essentially all it does is export a method into your namespace that 
looks through a search path for .pm files and turn those into class names. 

Optionally it instantiates those classes for you.

=head1 ADVANCED USAGE

Alternatively, if you don't want to use 'plugins' as the method ...

    package MyClass;
    use Module::Pluggable sub_name => 'foo';


and then later ...

    my @plugins = $mc->foo();


Or if you want to look in another namespace

    package MyClass;
    use Module::Pluggable search_path => ['Acme::MyClass::Plugin', 'MyClass::Extend'];

or directory 

    use Module::Pluggable search_dirs => ['mylibs/Foo'];


Or if you want to instantiate each plugin rather than just return the name

    package MyClass;
    use Module::Pluggable instantiate => 'new';

and then

    # whatever is passed to 'plugins' will be passed 
    # to 'new' for each plugin 
    my @plugins = $mc->plugins(@options); 


alternatively you can just require the module without instantiating it

    package MyClass;
    use Module::Pluggable require => 1;

since requiring automatically searches inner packages, which may not be desirable, you can turn this off


    package MyClass;
    use Module::Pluggable require => 1, inner => 0;


You can limit the plugins loaded using the except option, either as a string,
array ref or regex

    package MyClass;
    use Module::Pluggable except => 'MyClass::Plugin::Foo';

or

    package MyClass;
    use Module::Pluggable except => ['MyClass::Plugin::Foo', 'MyClass::Plugin::Bar'];

or

    package MyClass;
    use Module::Pluggable except => qr/^MyClass::Plugin::(Foo|Bar)$/;


and similarly for only which will only load plugins which match.

Remember you can use the module more than once

    package MyClass;
    use Module::Pluggable search_path => 'MyClass::Filters' sub_name => 'filters';
    use Module::Pluggable search_path => 'MyClass::Plugins' sub_name => 'plugins';

and then later ...

    my @filters = $self->filters;
    my @plugins = $self->plugins;
    
=head1 PLUGIN SEARCHING

Every time you call 'plugins' the whole search path is walked again. This allows 
for dynamically loading plugins even at run time. However this can get expensive 
and so if you don't expect to want to add new plugins at run time you could do


  package Foo;
  use strict;
  use Module::Pluggable sub_name => '_plugins';

  our @PLUGINS;
  sub plugins { @PLUGINS ||= shift->_plugins }
  1;

=head1 INNER PACKAGES

If you have, for example, a file B<lib/Something/Plugin/Foo.pm> that
contains package definitions for both C<Something::Plugin::Foo> and 
C<Something::Plugin::Bar> then as long as you either have either 
the B<require> or B<instantiate> option set then we'll also find 
C<Something::Plugin::Bar>. Nifty!

=head1 OPTIONS

You can pass a hash of options when importing this module.

The options can be ...

=head2 sub_name

The name of the subroutine to create in your namespace. 

By default this is 'plugins'

=head2 search_path

An array ref of namespaces to look in. 

=head2 search_dirs 

An array ref of directorys to look in before @INC.

=head2 instantiate

Call this method on the class. In general this will probably be 'new'
but it can be whatever you want. Whatever arguments are passed to 'plugins' 
will be passed to the method.

The default is 'undef' i.e just return the class name.

=head2 require

Just require the class, don't instantiate (overrides 'instantiate');

=head2 inner

If set to 0 will B<not> search inner packages. 
If set to 1 will override C<require>.

=head2 only

Takes a string, array ref or regex describing the names of the only plugins to 
return. Whilst this may seem perverse ... well, it is. But it also 
makes sense. Trust me.

=head2 except

Similar to C<only> it takes a description of plugins to exclude 
from returning. This is slightly less perverse.

=head2 package

This is for use by extension modules which build on C<Module::Pluggable>:
passing a C<package> option allows you to place the plugin method in a
different package other than your own.

=head2 file_regex

By default C<Module::Pluggable> only looks for I<.pm> files.

By supplying a new C<file_regex> then you can change this behaviour e.g

    file_regex => qr/\.plugin$/

=head2 include_editor_junk

By default C<Module::Pluggable> ignores files that look like they were
left behind by editors. Currently this means files ending in F<~> (~),
the extensions F<.swp> or F<.swo>, or files beginning with F<.#>.

Setting C<include_editor_junk> changes C<Module::Pluggable> so it does
not ignore any files it finds.

=head2 follow_symlinks

Whether, when searching directories, to follow symlinks.

Defaults to 1 i.e do follow symlinks.

=head2 min_depth, max_depth

This will allow you to set what 'depth' of plugin will be allowed.

So, for example, C<MyClass::Plugin::Foo> will have a depth of 3 and 
C<MyClass::Plugin::Foo::Bar> will have a depth of 4 so to only get the former 
(i.e C<MyClass::Plugin::Foo>) do

        package MyClass;
        use Module::Pluggable max_depth => 3;
        
and to only get the latter (i.e C<MyClass::Plugin::Foo::Bar>)

        package MyClass;
        use Module::Pluggable min_depth => 4;


=head1 TRIGGERS

Various triggers can also be passed in to the options.

If any of these triggers return 0 then the plugin will not be returned.

=head2 before_require <plugin>

Gets passed the plugin name. 

If 0 is returned then this plugin will not be required either.

=head2 on_require_error <plugin> <err>

Gets called when there's an error on requiring the plugin.

Gets passed the plugin name and the error. 

The default on_require_error handler is to C<carp> the error and return 0.

=head2 on_instantiate_error <plugin> <err>

Gets called when there's an error on instantiating the plugin.

Gets passed the plugin name and the error. 

The default on_instantiate_error handler is to C<carp> the error and return 0.

=head2 after_require <plugin>

Gets passed the plugin name. 

If 0 is returned then this plugin will be required but not returned as a plugin.

=head1 METHODs

=head2 search_path

The method C<search_path> is exported into you namespace as well. 
You can call that at any time to change or replace the 
search_path.

    $self->search_path( add => "New::Path" ); # add
    $self->search_path( new => "New::Path" ); # replace

=head1 BEHAVIOUR UNDER TEST ENVIRONMENT

In order to make testing reliable we exclude anything not from blib if blib.pm is 
in %INC. 

However if the module being tested used another module that itself used C<Module::Pluggable> 
then the second module would fail. This was fixed by checking to see if the caller 
had (^|/)blib/ in their filename.

There's an argument that this is the wrong behaviour and that modules should explicitly
trigger this behaviour but that particular code has been around for 7 years now and I'm 
reluctant to change the default behaviour.

You can now (as of version 4.1) force Module::Pluggable to look outside blib in a test environment by doing either

        require Module::Pluggable;
        $Module::Pluggable::FORCE_SEARCH_ALL_PATHS = 1;
        import Module::Pluggable;

or

        use Module::Pluggable force_search_all_paths => 1;
        

=head1 FUTURE PLANS

This does everything I need and I can't really think of any other 
features I want to add. Famous last words of course

Recently tried fixed to find inner packages and to make it 
'just work' with PAR but there are still some issues.


However suggestions (and patches) are welcome.

=head1 DEVELOPMENT

The master repo for this module is at

https://github.com/simonwistow/Module-Pluggable

=head1 AUTHOR

Simon Wistow <simon@thegestalt.org>

=head1 COPYING

Copyright, 2006 Simon Wistow

Distributed under the same terms as Perl itself.

=head1 BUGS

None known.

=head1 SEE ALSO

L<File::Spec>, L<File::Find>, L<File::Basename>, L<Class::Factory::Util>, L<Module::Pluggable::Ordered>

=cut 


package Module::Pluggable::Object;

use strict;
use File::Find ();
use File::Basename;
use File::Spec::Functions qw(splitdir catdir curdir catfile abs2rel);
use Carp qw(croak carp confess);
use Devel::InnerPackage;
use vars qw($VERSION);

use if $] > 5.017, 'deprecate';

$VERSION = '4.6';


sub new {
    my $class = shift;
    my %opts  = @_;

    return bless \%opts, $class;

}

### Eugggh, this code smells 
### This is what happens when you keep adding patches
### *sigh*


sub plugins {
    my $self = shift;
    my @args = @_;

    # override 'require'
    $self->{'require'} = 1 if $self->{'inner'};

    my $filename   = $self->{'filename'};
    my $pkg        = $self->{'package'};

    # Get the exception params instantiated
    $self->_setup_exceptions;

    # automatically turn a scalar search path or namespace into a arrayref
    for (qw(search_path search_dirs)) {
        $self->{$_} = [ $self->{$_} ] if exists $self->{$_} && !ref($self->{$_});
    }

    # default search path is '<Module>::<Name>::Plugin'
    $self->{'search_path'} ||= ["${pkg}::Plugin"]; 

    # default error handler
    $self->{'on_require_error'} ||= sub { my ($plugin, $err) = @_; carp "Couldn't require $plugin : $err"; return 0 };
    $self->{'on_instantiate_error'} ||= sub { my ($plugin, $err) = @_; carp "Couldn't instantiate $plugin: $err"; return 0 };

    # default whether to follow symlinks
    $self->{'follow_symlinks'} = 1 unless exists $self->{'follow_symlinks'};

    # check to see if we're running under test
    my @SEARCHDIR = exists $INC{"blib.pm"} && defined $filename && $filename =~ m!(^|/)blib/! && !$self->{'force_search_all_paths'} ? grep {/blib/} @INC : @INC;

    # add any search_dir params
    unshift @SEARCHDIR, @{$self->{'search_dirs'}} if defined $self->{'search_dirs'};

    # set our @INC up to include and prefer our search_dirs if necessary
    my @tmp = @INC;
    unshift @tmp, @{$self->{'search_dirs'} || []};
    local @INC = @tmp if defined $self->{'search_dirs'};

    my @plugins = $self->search_directories(@SEARCHDIR);
    push(@plugins, $self->handle_innerpackages($_)) for @{$self->{'search_path'}};
    
    # return blank unless we've found anything
    return () unless @plugins;

    # remove duplicates
    # probably not necessary but hey ho
    my %plugins;
    for(@plugins) {
        next unless $self->_is_legit($_);
        $plugins{$_} = 1;
    }

    # are we instantiating or requring?
    if (defined $self->{'instantiate'}) {
        my $method = $self->{'instantiate'};
        my @objs   = ();
        foreach my $package (sort keys %plugins) {
            next unless $package->can($method);
            my $obj = eval { $package->$method(@_) };
            $self->{'on_instantiate_error'}->($package, $@) if $@;
            push @objs, $obj if $obj;           
        }
        return @objs;
    } else { 
        # no? just return the names
        my @objs= sort keys %plugins;
        return @objs;
    }
}

sub _setup_exceptions {
    my $self = shift;

    my %only;   
    my %except; 
    my $only;
    my $except;

    if (defined $self->{'only'}) {
        if (ref($self->{'only'}) eq 'ARRAY') {
            %only   = map { $_ => 1 } @{$self->{'only'}};
        } elsif (ref($self->{'only'}) eq 'Regexp') {
            $only = $self->{'only'}
        } elsif (ref($self->{'only'}) eq '') {
            $only{$self->{'only'}} = 1;
        }
    }
        

    if (defined $self->{'except'}) {
        if (ref($self->{'except'}) eq 'ARRAY') {
            %except   = map { $_ => 1 } @{$self->{'except'}};
        } elsif (ref($self->{'except'}) eq 'Regexp') {
            $except = $self->{'except'}
        } elsif (ref($self->{'except'}) eq '') {
            $except{$self->{'except'}} = 1;
        }
    }
    $self->{_exceptions}->{only_hash}   = \%only;
    $self->{_exceptions}->{only}        = $only;
    $self->{_exceptions}->{except_hash} = \%except;
    $self->{_exceptions}->{except}      = $except;
        
}

sub _is_legit {
    my $self   = shift;
    my $plugin = shift;
    my %only   = %{$self->{_exceptions}->{only_hash}||{}};
    my %except = %{$self->{_exceptions}->{except_hash}||{}};
    my $only   = $self->{_exceptions}->{only};
    my $except = $self->{_exceptions}->{except};
    my $depth  = () = split '::', $plugin, -1;

    return 0 if     (keys %only   && !$only{$plugin}     );
    return 0 unless (!defined $only || $plugin =~ m!$only!     );

    return 0 if     (keys %except &&  $except{$plugin}   );
    return 0 if     (defined $except &&  $plugin =~ m!$except! );
    
    return 0 if     defined $self->{max_depth} && $depth>$self->{max_depth};
    return 0 if     defined $self->{min_depth} && $depth<$self->{min_depth};

    return 1;
}

sub search_directories {
    my $self      = shift;
    my @SEARCHDIR = @_;

    my @plugins;
    # go through our @INC
    foreach my $dir (@SEARCHDIR) {
        push @plugins, $self->search_paths($dir);
    }
    return @plugins;
}


sub search_paths {
    my $self = shift;
    my $dir  = shift;
    my @plugins;

    my $file_regex = $self->{'file_regex'} || qr/\.pm$/;


    # and each directory in our search path
    foreach my $searchpath (@{$self->{'search_path'}}) {
        # create the search directory in a cross platform goodness way
        my $sp = catdir($dir, (split /::/, $searchpath));

        # if it doesn't exist or it's not a dir then skip it
        next unless ( -e $sp && -d _ ); # Use the cached stat the second time

        my @files = $self->find_files($sp);

        # foreach one we've found 
        foreach my $file (@files) {
            # untaint the file; accept .pm only
            next unless ($file) = ($file =~ /(.*$file_regex)$/); 
            # parse the file to get the name
            my ($name, $directory, $suffix) = fileparse($file, $file_regex);

            next if (!$self->{include_editor_junk} && $self->_is_editor_junk($name));

            $directory = abs2rel($directory, $sp);

            # If we have a mixed-case package name, assume case has been preserved
            # correctly.  Otherwise, root through the file to locate the case-preserved
            # version of the package name.
            my @pkg_dirs = ();
            if ( $name eq lc($name) || $name eq uc($name) ) {
                my $pkg_file = catfile($sp, $directory, "$name$suffix");
                open PKGFILE, "<$pkg_file" or die "search_paths: Can't open $pkg_file: $!";
                my $in_pod = 0;
                while ( my $line = <PKGFILE> ) {
                    $in_pod = 1 if $line =~ m/^=\w/;
                    $in_pod = 0 if $line =~ /^=cut/;
                    next if ($in_pod || $line =~ /^=cut/);  # skip pod text
                    next if $line =~ /^\s*#/;               # and comments
                    if ( $line =~ m/^\s*package\s+(.*::)?($name)\s*;/i ) {
                        @pkg_dirs = split /::/, $1 if defined $1;;
                        $name = $2;
                        last;
                    }
                }
                close PKGFILE;
            }

            # then create the class name in a cross platform way
            $directory =~ s/^[a-z]://i if($^O =~ /MSWin32|dos/);       # remove volume
            my @dirs = ();
            if ($directory) {
                ($directory) = ($directory =~ /(.*)/);
                @dirs = grep(length($_), splitdir($directory)) 
                    unless $directory eq curdir();
                for my $d (reverse @dirs) {
                    my $pkg_dir = pop @pkg_dirs; 
                    last unless defined $pkg_dir;
                    $d =~ s/\Q$pkg_dir\E/$pkg_dir/i;  # Correct case
                }
            } else {
                $directory = "";
            }
            my $plugin = join '::', $searchpath, @dirs, $name;

            next unless $plugin =~ m!(?:[a-z\d]+)[a-z\d]!i;

            $self->handle_finding_plugin($plugin, \@plugins)
        }

        # now add stuff that may have been in package
        # NOTE we should probably use all the stuff we've been given already
        # but then we can't unload it :(
        push @plugins, $self->handle_innerpackages($searchpath);
    } # foreach $searchpath

    return @plugins;
}

sub _is_editor_junk {
    my $self = shift;
    my $name = shift;

    # Emacs (and other Unix-y editors) leave temp files ending in a
    # tilde as a backup.
    return 1 if $name =~ /~$/;
    # Emacs makes these files while a buffer is edited but not yet
    # saved.
    return 1 if $name =~ /^\.#/;
    # Vim can leave these files behind if it crashes.
    return 1 if $name =~ /\.sw[po]$/;

    return 0;
}

sub handle_finding_plugin {
    my $self    = shift;
    my $plugin  = shift;
    my $plugins = shift;
    my $no_req  = shift || 0;
    
    return unless $self->_is_legit($plugin);
    unless (defined $self->{'instantiate'} || $self->{'require'}) {
        push @$plugins, $plugin;
        return;
    } 

    $self->{before_require}->($plugin) || return if defined $self->{before_require};
    unless ($no_req) {
        my $tmp = $@;
        my $res = eval { $self->_require($plugin) };
        my $err = $@;
        $@      = $tmp;
        if ($err) {
            if (defined $self->{on_require_error}) {
                $self->{on_require_error}->($plugin, $err) || return; 
            } else {
                return;
            }
        }
    }
    $self->{after_require}->($plugin) || return if defined $self->{after_require};
    push @$plugins, $plugin;
}

sub find_files {
    my $self         = shift;
    my $search_path  = shift;
    my $file_regex   = $self->{'file_regex'} || qr/\.pm$/;


    # find all the .pm files in it
    # this isn't perfect and won't find multiple plugins per file
    #my $cwd = Cwd::getcwd;
    my @files = ();
    { # for the benefit of perl 5.6.1's Find, localize topic
        local $_;
        File::Find::find( { no_chdir => 1, 
                            follow   => $self->{'follow_symlinks'}, 
                            wanted   => sub { 
                             # Inlined from File::Find::Rule C< name => '*.pm' >
                             return unless $File::Find::name =~ /$file_regex/;
                             (my $path = $File::Find::name) =~ s#^\\./##;
                             push @files, $path;
                           }
                      }, $search_path );
    }
    #chdir $cwd;
    return @files;

}

sub handle_innerpackages {
    my $self = shift;
    return () if (exists $self->{inner} && !$self->{inner});

    my $path = shift;
    my @plugins;

    foreach my $plugin (Devel::InnerPackage::list_packages($path)) {
        $self->handle_finding_plugin($plugin, \@plugins, 1);
    }
    return @plugins;

}


sub _require {
    my $self   = shift;
    my $pack   = shift;
    eval "CORE::require $pack";
    die ($@) if $@;
    return 1;
}


1;

=pod

=head1 NAME

Module::Pluggable::Object - automatically give your module the ability to have plugins

=head1 SYNOPSIS


Simple use Module::Pluggable -

    package MyClass;
    use Module::Pluggable::Object;
    
    my $finder = Module::Pluggable::Object->new(%opts);
    print "My plugins are: ".join(", ", $finder->plugins)."\n";

=head1 DESCRIPTION

Provides a simple but, hopefully, extensible way of having 'plugins' for 
your module. Obviously this isn't going to be the be all and end all of
solutions but it works for me.

Essentially all it does is export a method into your namespace that 
looks through a search path for .pm files and turn those into class names. 

Optionally it instantiates those classes for you.

This object is wrapped by C<Module::Pluggable>. If you want to do something
odd or add non-general special features you're probably best to wrap this
and produce your own subclass.

=head1 OPTIONS

See the C<Module::Pluggable> docs.

=head1 AUTHOR

Simon Wistow <simon@thegestalt.org>

=head1 COPYING

Copyright, 2006 Simon Wistow

Distributed under the same terms as Perl itself.

=head1 BUGS

None known.

=head1 SEE ALSO

L<Module::Pluggable>

=cut 

package Devel::InnerPackage;

use strict;
use base qw(Exporter);
use vars qw($VERSION @EXPORT_OK);

use if $] > 5.017, 'deprecate';

$VERSION = '0.4';
@EXPORT_OK = qw(list_packages);

=pod

=head1 NAME

Devel::InnerPackage - find all the inner packages of a package

=head1 SYNOPSIS

    use Foo::Bar;
    use Devel::InnerPackage qw(list_packages);

    my @inner_packages = list_packages('Foo::Bar');


=head1 DESCRIPTION


Given a file like this


    package Foo::Bar;

    sub foo {}


    package Foo::Bar::Quux;

    sub quux {}

    package Foo::Bar::Quirka;

    sub quirka {}

    1;

then

    list_packages('Foo::Bar');

will return

    Foo::Bar::Quux
    Foo::Bar::Quirka

=head1 METHODS

=head2 list_packages <package name>

Return a list of all inner packages of that package.

=cut

sub list_packages {
            my $pack = shift; $pack .= "::" unless $pack =~ m!::$!;

            no strict 'refs';
            my @packs;
            my @stuff = grep !/^(main|)::$/, keys %{$pack};
            for my $cand (grep /::$/, @stuff)
            {
                $cand =~ s!::$!!;
                my @children = list_packages($pack.$cand);
    
                push @packs, "$pack$cand" unless $cand =~ /^::/ ||
                    !__PACKAGE__->_loaded($pack.$cand); # or @children;
                push @packs, @children;
            }
            return grep {$_ !~ /::(::ISA::CACHE|SUPER)/} @packs;
}

### XXX this is an inlining of the Class-Inspector->loaded()
### method, but inlined to remove the dependency.
sub _loaded {
       my ($class, $name) = @_;

        no strict 'refs';

       # Handle by far the two most common cases
       # This is very fast and handles 99% of cases.
       return 1 if defined ${"${name}::VERSION"};
       return 1 if @{"${name}::ISA"};

       # Are there any symbol table entries other than other namespaces
       foreach ( keys %{"${name}::"} ) {
               next if substr($_, -2, 2) eq '::';
               return 1 if defined &{"${name}::$_"};
       }

       # No functions, and it doesn't have a version, and isn't anything.
       # As an absolute last resort, check for an entry in %INC
       my $filename = join( '/', split /(?:'|::)/, $name ) . '.pm';
       return 1 if defined $INC{$filename};

       '';
}


=head1 AUTHOR

Simon Wistow <simon@thegestalt.org>

=head1 COPYING

Copyright, 2005 Simon Wistow

Distributed under the same terms as Perl itself.

=head1 BUGS

None known.

=cut 





1;
