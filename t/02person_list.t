#!/usr/bin/env perl

use 5.024;
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
  new(config_stems => [ path('person_list')->absolute($FindBin::Bin)->canonpath ]);

my $handle = PEDSnet::Derivation::Anthro_Z->new( src_backend => $backend,
						 sink_backend => $backend,
						 config => $config );


my $gq = $backend->build_query('select * from ' .
			       $config->input_measurement_table);
$gq->execute;
my $test_list = $backend->fetch_chunk($gq);


my $q = eval { $handle->get_meas_for_person_qry };
my $error = $@;

isa_ok($q, 'Rose::DBx::CannedQuery', 'Ht/wt retrieval query');
is($error, '', 'No error constructing query');
ok($q->execute(2), 'Execute for test person');

my $list = eval { $backend->fetch_chunk($q); };
$error = $@;
$error = 'No results' if $error eq '' and not @$list;

is($error, '', 'No error executing query');
eq_or_diff($list,
	   [ grep { $_->{person_id} == 2 } @$test_list ],
	   'Result is correct');


eval {
  # Suppress error message if table doesn't exist
  local $SIG{__WARN__} = sub {};
  my $dbh = $backend->rdb->dbh;
  $dbh->do('drop table ' .
	   $dbh->quote_identifier($config->output_measurement_table));
};
$backend->clone_table($config->input_measurement_table,
		      $config->output_measurement_table);


my $person_list =
  $backend->build_query('select * from ' .
			$config->input_person_table)->execute->fetchall_arrayref({});

my @expected =
  path('person_list_output_expected')->absolute($FindBin::Bin)->lines;

s/computation v[0-9.]+/computation v$PEDSnet::Derivation::Anthro_Z::VERSION/ for @expected;
s/(\d*)\.(\d\d)\d+/$1.$2/g for @expected;


is($handle->process_person_chunk($person_list), @expected - 1, 'Process person list');

$handle->flush_output;

my $outp = path($config->output_measurement_table)->
	   absolute($FindBin::Bin);
my @got = $outp->lines;

s/(\d*)\.(\d\d)\d+/$1.$2/g for @got;

$outp->remove
  if eq_or_diff(\@got, \@expected, 'Output is correct');

done_testing;

