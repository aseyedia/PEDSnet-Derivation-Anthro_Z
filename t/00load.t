#!/usr/bin/env perl

use Test::More;

use PEDSnet::Derivation::Backend::CSV;

require_ok('PEDSnet::Derivation::Anthro_Z');

my $backend = PEDSnet::Derivation::Backend::CSV->new(db_dir => '.');

new_ok('PEDSnet::Derivation::Anthro_Z',
       [ src_backend => $backend, sink_backend => $backend ]);

done_testing();

