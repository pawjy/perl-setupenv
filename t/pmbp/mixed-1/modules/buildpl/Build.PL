use strict;
use warnings;
use Module::Build;

my $build = Module::Build->new(
    license              => 'perl',
    dynamic_config       => 0,

    requires             => {
        'Log::Dispatch'        => 0,
    },

    name        => 'Test1',
    module_name => 'Test1',
);
$build->create_build_script();
