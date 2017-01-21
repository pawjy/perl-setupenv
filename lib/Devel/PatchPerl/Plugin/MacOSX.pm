package Devel::PatchPerl::Plugin::MacOSX;
use strict;
use warnings;
use Devel::PatchPerl;
push our @ISA, qw(Devel::PatchPerl);
our $VERSION = '1.0';

sub patchperl {
  my $class = shift;
  my %args = @_;
  my ($vers, $source, $patch_exe) = @args{qw(version source patchexe)};
  for my $p ( grep { Devel::PatchPerl::_is( $_->{perl}, $vers ) } @Devel::PatchPerl::patch ) {
    for my $s (@{$p->{subs}}) {
      my ($sub, @args) = @$s;
      push @args, $vers unless scalar @args;
      $sub->(@args);
    }
  }
}

package Devel::PatchPerl;

our @patch = (
  {
    perl => [ qr/^5\.24\.[01]$/ ],
    subs => [ [ \&_time_hires ] ],
  },
);

sub _time_hires {
  _patch(<<'END');
--- dist/Time-HiRes/HiRes.xs
+++ dist/Time-HiRes/HiRes.xs
@@ -940,7 +940,7 @@ BOOT:
   }
 #   endif
 #endif
-#if defined(PERL_DARWIN)
+#if defined(PERL_DARWIN) && !defined(CLOCK_REALTIME)
 #  ifdef USE_ITHREADS
   MUTEX_INIT(&darwin_time_mutex);
 #  endif
END
}

1;

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
