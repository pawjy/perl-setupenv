use strict;
use warnings;

local $/ = undef;
my $html = <>;

$html =~ m{
  <a\s+href="/release/([A-Z]+)/perl-([0-9][0-9.]+[0-9])">This\s+version</a>
}x
    or die "Failed to extract Perl version";

my $author_name = $1;
my $perl_version = $2;

# authors/id/S/SH/SHAY/perl-5.26.1.tar.gz
my $perl_cpan_path = sprintf 'authors/id/%s/%s/%s/perl-%s.tar.gz',
    (substr $author_name, 0, 1),
    (substr $author_name, 0, 2),
    $author_name,
    $perl_version;

{
  open my $file, '>', 'version/perl.txt' or die "$0: version/perl.txt: $!";
  print $file $perl_version;
}
{
  open my $file, '>', 'version/perl-cpan-path.txt' or die "$0: version/perl-cpan-path.txt: $!";
  print $file $perl_cpan_path;
}

## License: Public Domain.
