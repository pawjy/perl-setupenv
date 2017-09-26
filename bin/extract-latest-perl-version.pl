use strict;
use warnings;

local $/ = undef;
my $html = <>;

$html =~ m{
  <td[^<>]+>Latest\s+Release</td> \s*
  <td[^<>]+><a[^<>]+>perl-([0-9.]+)</a></td> \s*
  <td><small>&nbsp;\[<a\s+href="/CPAN/(authors/id/[^"]+?/perl-[^"]+)">Download</a>\]
}x or
$html =~ m{
  <td[^<>]+>This\s+Release</td> \s*
  <td[^<>]+>perl-([0-9.]+)</td> \s*
  <td><small>&nbsp;\[<a\s+href="/CPAN/(authors/id/[^"]+?/perl-[^"]+)">Download</a>\]
}x
    or die "Failed to extract Perl version";

my $perl_version = $1;
my $perl_cpan_path = $2;

{
  open my $file, '>', 'version/perl.txt' or die "$0: version/perl.txt: $!";
  print $file $perl_version;
}
{
  open my $file, '>', 'version/perl-cpan-path.txt' or die "$0: version/perl-cpan-path.txt: $!";
  print $file $perl_cpan_path;
}

## License: Public Domain.
