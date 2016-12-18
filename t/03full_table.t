#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use Path::Tiny;
use Test::More;
use Test::Differences;

use PEDSnet::Derivation::Backend::CSV;

use PEDSnet::Derivation::Anthro_Z;
use PEDSnet::Derivation::Anthro_Z::Config;

my $backend = PEDSnet::Derivation::Backend::CSV->new(db_dir => $FindBin::Bin);
my $config = PEDSnet::Derivation::Anthro_Z::Config->
  new(config_stems => [ path('full_table')->absolute($FindBin::Bin)->canonpath ]);

my $handle = PEDSnet::Derivation::Anthro_Z->new( src_backend => $backend,
						 sink_backend => $backend,
						 config => $config );


eval {
  # Suppress error message if table doesn't exist
  local $SIG{__WARN__} = sub {};
  my $dbh = $backend->rdb->dbh;
  $dbh->do('drop table ' .
	   $dbh->quote_identifier($config->output_measurement_table));
};
$backend->clone_table($config->input_measurement_table,
		      $config->output_measurement_table);


my @expected =
  path('full_table_output_expected')->absolute($FindBin::Bin)->lines;

s/computation v[0-9.]+/computation v$PEDSnet::Derivation::Anthro_Z::VERSION/ for @expected;
s/(\d*)\.(\d\d)\d+/$1.$2/g for @expected;

is($handle->generate_zs, @expected - 1, 'Process full table');

my $outp = path($config->output_measurement_table)->
	   absolute($FindBin::Bin); 
my @got = $outp->lines;

s/(\d*)\.(\d\d)\d+/$1.$2/g for @got;

$outp->remove
  if eq_or_diff(\@got, \@expected, 'Output is correct');

done_testing;

