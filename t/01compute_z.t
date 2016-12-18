#!/usr/bin/env perl

use Test::More;

use PEDSnet::Derivation::Anthro_Z;
use PEDSnet::Derivation::Backend::CSV;

my $backend = PEDSnet::Derivation::Backend::CSV->new(db_dir => '.');

my $handle = PEDSnet::Derivation::Anthro_Z->new( src_backend => $backend,
					    sink_backend => $backend );
isa_ok($handle->get_measure_class( measure => 'WtAge', age => 48, sex => 'M'),
      'Medical::Growth::NHANES_2000::Base');

cmp_ok( int( 100 * $handle->compute_z('HtAge', 'F', 60, 110) ),
	'==', 48, 'Basic Z computation' );


done_testing();
