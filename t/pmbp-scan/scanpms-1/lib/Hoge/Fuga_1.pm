package Hoge::Fuga_1;
use strict;
use parent qw(Hoge Error);
use base qw(MIME::Base64);
extends 'Exporter::Lite'; # Moose style
use overload '""' => sub { };

1;
