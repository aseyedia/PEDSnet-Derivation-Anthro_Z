#!perl
#

use 5.010;
use strict;
use warnings;

package PEDSnet::Derivation::Anthro_Z::Config;

our($VERSION) = '0.01';

use Moo 2;
use Types::Standard qw/ Maybe Bool Str Int ArrayRef HashRef /;

extends 'PEDSnet::Derivation::Config';

sub _build_config_param {
  my( $self, $param_name, $sql_where ) = @_;
  my $val = $self->config_datum($param_name);
  return $val if defined $val;

  return unless defined $sql_where;
  my @cids = $self->ask_rdb('SELECT concept_id FROM concept WHERE ' . $sql_where);
  return $cids[0]->{concept_id};
}

# $_->{measurement_concept_id} = measurement for which Z score
# $_->{z_score_info}->{z_class_measure} - measure name for M::G
# $_->{z_score_info}->{z_measurement_concept_id} - CID for Z score

has 'concept_id_map' =>
  ( isa => ArrayRef, is => 'ro', required => 0,
    lazy => 1, builder => 'build_concept_id_map');

sub build_concept_id_map {
  my $self = shift;
  my $map = $self->config_datum('concept_id_map');
  return unless $map;

  if (ref($map) eq 'HASH') {
    # If Config::General merged a set of mapping definitions,
    # we need to unwind them.  We do this here because merging
    # duplicates is generally the right thing in Config::General;
    # this just happens to be an exception.
    if (ref($map->{measurement_concept_id}) =~ /^ARRAY/) {
      my @unwound = map { {} } $map->{measurement_concept_id}->@*;
      my $unwind;
      $unwind = sub {
	my($orig, $targ) = @_;
	foreach my $k (keys %$orig) {
	  if (ref($orig->{$k}) eq 'ARRAY') {
	    foreach my $idx ( 0 .. $#{ $orig->{$k} }) {
	      $targ->[$idx]->{$k} = $orig->{$k}->[$idx];
	    }
	  }
	  elsif (ref($orig->{$k}) eq 'HASH') {
	    $unwind->($orig->{$k},
		      [ map { $targ->[$_]->{$k} = {};
			      $targ->[$_]->{$k} } 0 .. $#{$targ} ]);
	  }
	}
	$targ;
      };
      $map = $unwind->($map, \@unwound);
    }
    else {
      $map = [ $map ];
    }
  }
  $map;
}


has 'z_measurement_type_concept_id' =>
  ( isa => Int, is => 'ro', required => 0,
    lazy => 1, builder => 'build_z_measurement_type_concept_id' );

sub build_z_measurement_type_concept_id {
  shift->_build_config_param('z_measurement_type_concept_id',
			     q[concept_class_id = 'Meas Type' and 
                               concept_name = 'Derived value']);
}

has 'z_unit_concept_id' =>
  ( isa => Int, is => 'ro', required => 1,
    lazy => 1, builder => 'build_z_unit_concept_id' );

sub build_z_unit_concept_id {
  shift->_build_config_param('z_unit_concept_id') // 0;
}

has 'z_unit_source_value' =>
  ( isa => Maybe[Str], is => 'ro', required => 1,
    lazy => 1, builder => 'build_z_unit_source_value' );

sub build_z_unit_source_value {
  shift->_build_config_param('z_unit_source_value') // undef;
}


has 'input_measurement_table' =>
  ( isa => Str, is => 'ro', required => 1, lazy => 1,
    builder => 'build_input_measurement_table' );

sub build_input_measurement_table {
  shift->_build_config_param('input_measurement_table') // 'measurement';
}

has 'input_person_table' =>
  ( isa => Str, is => 'ro', required => 1, lazy => 1,
    builder => 'build_input_person_table' );

sub build_input_person_table {
  shift->_build_config_param('input_person_table') // 'person';
}

has 'output_measurement_table' =>
  ( isa => Str, is => 'ro', required => 1, lazy => 1,
    builder => 'build_output_measurement_table' );

sub build_output_measurement_table {
  shift->_build_config_param('output_measurement_table') // 'measurement';
}

has 'output_chunk_size' =>
  ( isa => Int, is => 'ro', required => 1, lazy => 1,
    builder => 'build_output_chunk_size' );

sub build_output_chunk_size {
  shift->_build_config_param('output_chunk_size') // 1000;
}

has 'person_chunk_size' =>
  ( isa => Int, is => 'ro', required => 1, lazy => 1,
    builder => 'build_person_chunk_size' );

sub build_person_chunk_size {
  shift->_build_config_param('person_chunk_size') // 1000;
}

has 'clone_z_measurements' =>
  ( isa => Bool, is => 'ro', required => 0, lazy => 1,
    builder => 'build_clone_z_measurements' );

sub build_clone_z_measurements {
  shift->_build_config_param('clone_z_measurements') // 0;
}

has 'clone_attributes_except' =>
  ( isa => ArrayRef, is => 'ro', required => 0, lazy => 1,
    builder => 'build_clone_attributes_except' );

sub build_clone_attributes_except {
  shift->_build_config_param('clone_attributes_except') //
    [ qw(measurement_id measurement_concept_id measurement_type_concept_id
         value_as_number value_as_concept_id unit_concept_id range_low range_high
         measurement_source_value measurement_source_concept_id unit_source_value
         value_source_value siteid) ];
}

1;
