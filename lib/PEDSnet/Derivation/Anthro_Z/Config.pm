#!perl
#

use 5.010;
use strict;
use warnings;

package PEDSnet::Derivation::Anthro_Z::Config;

our($VERSION) = '0.01';

=head1 NAME

PEDSnet::Derivation::Anthro_Z::Config - Configuration setting for Z score derivation

=head1 DESCRIPTION

Z score computation in L<PEDSnet::Derivation::Anthro_Z> depends both
on characteristics of the source data, such as what
C<measurement_concept_id>s are used for the measurements to be
normalized, and on conventions during computation, such as what
metadata to copy over from source
records. L<PEDSnet::Derivation::Anthro_Z::Config> allows you to make these
choices by setting attribute values, using the various options
described in L<PEDSnet::Derivation::Config>.

The following attributes are defined for the Z score derivation process:

=head2 Attributes

=for Pod::Coverage build_.+

=over 4

=cut

use Moo 2;
use Types::Standard qw/ Maybe Bool Str Int ArrayRef HashRef Enum /;

extends 'PEDSnet::Derivation::Config';

# TODO: Refactor into base class
sub _build_config_param {
  my( $self, $param_name, $sql_where ) = @_;
  my $val = $self->config_datum($param_name);
  return $val if defined $val;

  return unless defined $sql_where;
  my @cids = $self->ask_rdb('SELECT concept_id FROM concept WHERE ' . $sql_where);
  return $cids[0]->{concept_id};
}

=item concept_id_map

This attribute defines the relationship between specific measurement
types and the L<Medical::Growth> measurement systems used to compute Z
scores.  It is a refernece to an array of hash references, each of
which has two keys:

=over 4

=item measurement_concept_id

The C<measurement_concept_id> value to which this mapping applies.
This value is matched against measurement records to whether an
attempt should be made to derive a Z score using the specified
measurement system.

=item z_score_info

The associated value is itself a hash reference which describes the Z
score derivation.  Three keys are meaningful:

=over 4

=item z_class_system

The L<Medical::Growth> measurement system in which the class that will
compute the Z score will be found.

=item z_class_measure

The measurement name, known L</z_class_system>'s measurement system,
to be used for computing the Z score.  Both L</z_class_system> and
L</z_class_measure> will be passed to
L<Medical::Growth/get_measure_class_for> to obtain an object used to
compute the Z score.

=item z_check_callback

A Perl subroutine intended to check whether Z score computation should
proceed for a specific instance.  It is passed three arguments: the
person record and the measurement record to be tested, and the current
L</concept_id_map> record. If it returns a true value, Z score derivation is
attempted; if it returns false, the measurement record is ignored.

=item z_measurement_concept_id

If Z score computation is successful, the resulting measurement record
receives this value as its C<measurement_concept_id>.

=back

=back

For example, one might use the following to define BMI Z score
computation: 

  {
    measurement_concept_id => 3038553,
    z_score_info => {
      z_class_system => 'NHANES2000',
      z_class_measure => 'BMI for Age',
      z_measurement_concept_id => 2000000043,
      z_check_callback =>
        # Don't compute if less than 2 years of age
        sub {
          $_[1]->{measurement_dt}->delta_days($_[0]->{dt_of_birth})->delta_days
            > 365.25 * 2 ? 1 : 0
        }
      }
  }

=cut

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

  foreach my $m (@$map) {
    if (exists $m->{z_score_info}->{z_check_callback} and
	not ref $m->{z_score_info}->{z_check_callback}) {
      $m->{z_score_info}->{z_check_callback} =
	eval $m->{z_score_info}->{z_check_callback};
    }
  }

  $map;
}

=item z_measurement_type_concept_id

The C<measurement_type_concept_id> value to be used in newly-created Z
score records.

If no value is provided, an attempt is made to look up the concept
ID associated with C<Meas type> name C<Derived value>.

=cut

has 'z_measurement_type_concept_id' =>
  ( isa => Int, is => 'ro', required => 0,
    lazy => 1, builder => 'build_z_measurement_type_concept_id' );

sub build_z_measurement_type_concept_id {
  shift->_build_config_param('z_measurement_type_concept_id',
			     q[concept_class_id = 'Meas Type' and 
                               concept_name = 'Derived value']);
}

=item z_unit_concept_id

The C<unit_concept_id> value to be used in newly-created Z
score records.

If no value is provided, a default of C<0> is used.

=cut

has 'z_unit_concept_id' =>
  ( isa => Int, is => 'ro', required => 1,
    lazy => 1, builder => 'build_z_unit_concept_id' );

sub build_z_unit_concept_id {
  shift->_build_config_param('z_unit_concept_id') // 0;
}

=item z_unit_source_value

The C<unit_source_value> value to be used in newly-created Z
score records.

If no value is provided, the default is C<undef>.

=cut

has 'z_unit_source_value' =>
  ( isa => Maybe[Str], is => 'ro', required => 1,
    lazy => 1, builder => 'build_z_unit_source_value' );

sub build_z_unit_source_value {
  shift->_build_config_param('z_unit_source_value') // undef;
}

=item input_measurement_table

The name of the table in the source backend from which to read
measurements.  Defaults to C<measurement>.

=cut

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

=item output_measurement_table

The name of the table in the sink backend to which Z score
measurements are written.  Defaults to C<measurement>.

=cut

has 'output_measurement_table' =>
  ( isa => Str, is => 'ro', required => 1, lazy => 1,
    builder => 'build_output_measurement_table' );

sub build_output_measurement_table {
  shift->_build_config_param('output_measurement_table') // 'measurement';
}

=item output_chunk_size

It is often more efficient to write records to
L</output_measurement_table> in groups rather than individually, as
this permits the sink backend RDBMS to batch up insertions, foreign
key checks, etc.  To facilitate this, L<output_chunk_size> specifies
the number of Z score records that are cached and written together.
The risk, of course, is that if the connection to the sink is lost, or
the application encounters another fatal error, cached records are
lost.

Defaults to 1000.

=cut

has 'output_chunk_size' =>
  ( isa => Int, is => 'ro', required => 1, lazy => 1,
    builder => 'build_output_chunk_size' );

sub build_output_chunk_size {
  shift->_build_config_param('output_chunk_size') // 1000;
}

=item sql_flavor

Provides a hint about the complexity of SQL statement the source
backend can handle.  A value of C<limited> indicates that the backend
has limited range, as seen with C<DBD::CSV>, and queries should avoid
constructs such as subselects or multiple joins.  A value of C<full>
indicates that expressions such as these are ok.

Defaults to C<limited>, which produces less efficient SQL in some
case, but will work, albeit slowly, with a wider range of backends.

=cut

has 'sql_flavor' =>
  ( isa => Enum[ qw/ limited full /], is => 'ro', required => 0, lazy => 1,
    builder => 'build_sql_flavor' );

sub build_sql_flavor { shift->_build_config_param('sql_flavor') // 'limited' }

=item person_finder_sql

A string of SQL to be used to select the C<person_id>s for whom Z
scores should be computed.

The default value finds persons who have one or more measurements with
a C<measurement_concept_id> present in L</concept_id_map>.

=cut

has 'person_finder_sql' =>
  ( isa => Str, is => 'ro', required => 1, lazy => 1,
    builder => 'build_person_finder_sql' );

sub build_person_finder_sql {
  my $self = shift;

  my $sql = $self->_build_config_param('person_finder_sql');
  return $sql if $sql;

  # DBD::CSV has a hard time with explicit 3-table join
  # N.B. SQL::Statement requires capitalzation below
  if ($self->sql_flavor eq 'limited') {
    return q[select distinct p.person_id, p.time_of_birth,
                             c.concept_name as gender_name
             from ] . $self->input_person_table . q[ as p,
               ] . $self->input_measurement_table . q[ as m,
	       concept as c
	     where p.person_id = m.person_id 
               and p.gender_concept_id = c.concept_id
               and m.measurement_concept_id IN (] .
	  	 join(', ', map { $_->{measurement_concept_id} }
		      $self->concept_id_map->@*) . q[)];
  }
  else {
    return q[select distinct p.person_id, p.time_of_birth,
                            c.concept_name as gender_name
             from ] . $self->input_measurement_table . q[ m
             inner join ] . $self->input_person_table .
	       q[ p on p.person_id = m.person_id
             left join concept c ON c.concept_id = p.gender_concept_id
             where m.measurement_concept_id in (] . 
	       join(', ', map { $_->{measurement_concept_id} }
		    $self->concept_id_map->@*) . q[)];
  }
}

=item person_chunk_size

The number of C<person_id>s to retrieve at a time from the source
backend in L<PEDSnet::Derivation::Anthro_Z/generate_zs>.

Defaults to 1000.

=cut

has 'person_chunk_size' =>
  ( isa => Int, is => 'ro', required => 1, lazy => 1,
    builder => 'build_person_chunk_size' );

sub build_person_chunk_size {
  shift->_build_config_param('person_chunk_size') // 1000;
}

=item clone_z_measurements

When Z score records are constructed, a number of fields are set
directly, such as the value itself and the metadata indicating that
it's a Z score of a given type. For the rest of the fields in a
measurement record, you have two choices.  If L</clone_z_measurements>
is true, then the remaining values (e.g. dates, provider) are taken
from the measurement record that underlies the Z score.  If
L</clone_z_measurements> is false, then a known set of fields (from
the PEDSnet CDM definition) are copied from the base record, but any
other fields (such as custom fields you may have added in your
measurement table) are not.

Defaults to false as a conservative approach, but unless you've made
major modifications to measurement record structure, it's generally a
good idea to set this to a true value, and use
L</clone_attributes_except> to weed out any attributes you don't
want to carry over.

=cut

has 'clone_z_measurements' =>
  ( isa => Bool, is => 'ro', required => 0, lazy => 1,
    builder => 'build_clone_z_measurements' );

sub build_clone_z_measurements {
  shift->_build_config_param('clone_z_measurements') // 0;
}

=item clone_attributes_except

If L</clone_z_measurements> is true, then the value of
L</clone_attributes_except> is taken as a reference to an array of
attribute names that should NOT be carried over from the parent weight
record. 

Defaults to a list of attributes that specific to the fact that the
new record is a Z score.

=cut

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


__END__

=back

=head1 BUGS AND CAVEATS

Are there, for certain, but have yet to be cataloged.

=head1 VERSION

version 0.02

=head1 AUTHOR

Charles Bailey <cbail@cpan.org>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2016 by Charles Bailey

This software may be used under the terms of the Artistic License or
the GNU General Public License, as the user prefers.

This code was written at the Children's Hospital of Philadelphia as
part of L<PCORI|http://www.pcori.org>-funded work in the
L<PEDSnet|http://www.pedsnet.org> Data Coordinating Center.

=cut
