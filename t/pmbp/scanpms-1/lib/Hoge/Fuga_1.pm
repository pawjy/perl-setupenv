package Hoge::Fuga_1;
use strict;
use parent qw(Hoge Error);
use base qw(MIME::Base64);
use Exporter::Lite;
use overload '""' => sub { };

1;
