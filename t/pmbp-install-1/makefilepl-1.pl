BEGIN {
    use inc::Module::Install;

    my @mip = qw(
        Module::Install::AuthorTests
    );
    for (@mip) {
        eval "require $_";
        if ($@) {
            eval "require inc::$_";
            if ($@) {
                warn $@;
                printf("# Install following (perl Makefile.PL | cpanm):\n%s", join("\n", @mip));
                exit 1;
            }
        }
    }
}

name 'test1';
version '1.0';

requires 'Scalar::Util::Numeric';
recommends 'Exporter::Lite';

tests 't/*.t t/*/*.t t/*/*/*.t t/*/*/*/*.t';

test_requires 'Test::Name::FromLine';

WriteAll;
