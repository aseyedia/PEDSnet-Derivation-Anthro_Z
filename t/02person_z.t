#!/usr/bin/env perl

use 5.024;
use strict;
use warnings;

use Test::More;

use Rose::DateTime::Util qw(parse_date);

use PEDSnet::Derivation::Anthro_Z;
use PEDSnet::Derivation::Backend::CSV;

my $csvdb = PEDSnet::Derivation::Backend::CSV->
  new(db_dir => '.');

my $handle = PEDSnet::Derivation::Anthro_Z->
  new( src_backend => $csvdb, sink_backend => $csvdb);

my $person = {
	      person_id => 1,
	      gender_concept_id => 8532,
	      gender_name => 'FEMALE',
	      birth_datetime => parse_date('2015-09-05')->
	                       subtract(years => 4)->iso8601,
	     };

my $inputs = [
	      {
	       measurement_id => 1,
	       person_id => 1,
	       measurement_concept_id => 3023540,
	       measurement_type_concept_id => 2000000033,
	       measurement_date => '2015-04-01',
	       measurement_datetime => '2015-04-01T11:42:14',
	       value_as_number => 102,
	       provider_id => 1,
	       visit_occurrence_id => 1
	      },
	      {
	       measurement_id => 2,
	       person_id => 1,
	       measurement_concept_id => 3013762,
	       measurement_type_concept_id => 2000000033,
	       measurement_date => '2015-09-05',
	       measurement_datetime => '2015-09-05T14:10:14',
	       value_as_number => 15,
	       provider_id => 2,
	       visit_occurrence_id => 3,
	      },
	      {
	       measurement_id => 3,
	       person_id => 1,
	       measurement_concept_id => 3038553,
	       measurement_type_concept_id => 45754907,
	       unit_concept_id => 9531,
	       unit_source_value => 'kg/m2',
	       measurement_date => '2015-09-05',
	       measurement_datetime => '2015-09-05T14:10:14',
	       value_as_number => 13.6,
	       provider_id => 2,
	       visit_occurrence_id => 3,
	      },
	     ];

my $output = [
	      {
	       person_id => 1,
	       measurement_concept_id => 2000000042,
	       measurement_type_concept_id => 45754907,
	       measurement_date => '2015-04-01',
	       measurement_datetime => '2015-04-01T11:42:14',
	       value_as_number => 0.98,
	       unit_concept_id => 0,
	       unit_source_value => 'SD',
	       operator_concept_id => 4172703,
	       measurement_source_concept_id => 0,
	       provider_id => 1,
	       visit_occurrence_id => 1,
	       measurement_source_value =>
	       'PEDSnet NHANES 2000 Z score computation v' .
	         $PEDSnet::Derivation::Anthro_Z::VERSION,
	       value_source_value => 'measurement: 1'
	      },
	      {
	       person_id => 1,
	       measurement_concept_id => 2000000041,
	       measurement_type_concept_id => 45754907,
	       measurement_date => '2015-09-05',
	       measurement_datetime => '2015-09-05T14:10:14',
	       unit_concept_id => 0,
	       unit_source_value => 'SD',
	       value_as_number => -0.40,
	       operator_concept_id => 4172703,
	       measurement_source_concept_id => 0,
	       provider_id => 2,
	       visit_occurrence_id => 3,
	       measurement_source_value =>
	       'PEDSnet NHANES 2000 Z score computation v' .
	         $PEDSnet::Derivation::Anthro_Z::VERSION,
	       value_source_value => 'measurement: 2'
	      },
	      {
	       person_id => 1,
	       measurement_concept_id => 2000000043,
	       measurement_type_concept_id => 45754907,
	       measurement_date => '2015-09-05',
	       measurement_datetime => '2015-09-05T14:10:14',
	       value_as_number => -1.80,
	       unit_concept_id => 0,
	       unit_source_value => 'SD',
	       operator_concept_id => 4172703,
	       measurement_source_concept_id => 0,
	       provider_id => 2,
	       visit_occurrence_id => 3,
	       measurement_source_value =>
	       'PEDSnet NHANES 2000 Z score computation v' .
	         $PEDSnet::Derivation::Anthro_Z::VERSION,
	       value_source_value => 'measurement: 3'
	      },
	     ];

my $z_scores = eval { $handle->z_meas_for_person( $person, $inputs ) };
my $err = $@;

ok($z_scores, 'Computed Z score values');
is($err, '', 'No error');

$_->{value_as_number} = int( 100 * $_->{value_as_number} ) / 100 for @$z_scores;
is_deeply($z_scores, $output, 'Correct result');

$handle = PEDSnet::Derivation::Anthro_Z->
  new( src_backend => $csvdb, sink_backend => $csvdb,
       config => PEDSnet::Derivation::Anthro_Z::Config->
       new( config_overrides => { clone_z_measurements => 1 }));


$z_scores = $handle->z_meas_for_person( $person, [
	      {
	       measurement_id => 4,
	       person_id => 1,
	       measurement_concept_id => 3023540,
	       measurement_type_concept_id => 2000000033,
	       measurement_date => '2015-09-05',
	       measurement_datetime => '2015-09-05T14:42:14',
	       value_as_number => 102,
	       provider_id => 2,
	       visit_occurrence_id => 3
	      },
	      {
	       measurement_id => 6,
	       person_id => 1,
	       measurement_concept_id => 3013762,
	       measurement_type_concept_id => 2000000033,
	       measurement_date => '2015-09-05',
	       measurement_datetime => '2015-09-05T14:10:14',
	       value_as_number => 15,
	       provider_id => 2,
	       visit_occurrence_id => 3,
	       special_attr => 'Present',
	       other_attr => 'Also present'
	      } ] );
$_->{value_as_number} = int( 100 * $_->{value_as_number} ) / 100 for @$z_scores;

is_deeply( $z_scores,
	   [ {
	      person_id => 1,
	      measurement_concept_id => 2000000042,
	      measurement_type_concept_id => 45754907,
	      measurement_date => '2015-09-05',
	      measurement_datetime => '2015-09-05T14:42:14',
	      unit_concept_id => 0,
	      unit_source_value => 'SD',
	      operator_concept_id => 4172703,
	      value_as_number => 0.28,
	      provider_id => 2,
	      visit_occurrence_id => 3,
	      measurement_source_concept_id => 0,
	      measurement_source_value =>
	       'PEDSnet NHANES 2000 Z score computation v' .
	         $PEDSnet::Derivation::Anthro_Z::VERSION,
	      value_source_value => 'measurement: 4',
	     },
	     {
	      person_id => 1,
	      measurement_concept_id => 2000000041,
	      measurement_type_concept_id => 45754907,
	      measurement_date => '2015-09-05',
	      measurement_datetime => '2015-09-05T14:10:14',
	      unit_concept_id => 0,
	      unit_source_value => 'SD',
	      value_as_number => -0.40,
	      operator_concept_id => 4172703,
	      provider_id => 2,
	      visit_occurrence_id => 3,
	      measurement_source_concept_id => 0,
	      measurement_source_value =>
	       'PEDSnet NHANES 2000 Z score computation v' .
	         $PEDSnet::Derivation::Anthro_Z::VERSION,
	      value_source_value => 'measurement: 6',
	      other_attr => 'Also present'
	   }],
	   'Cloned Z score record'
	 );


done_testing;
