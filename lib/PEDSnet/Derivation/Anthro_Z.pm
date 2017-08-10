#!perl

use 5.024;
use strict;
use warnings;

package PEDSnet::Derivation::Anthro_Z;

our($VERSION) = '0.05';

use Moo 2;

use Rose::DateTime::Util qw( parse_date );
use Types::Standard qw/InstanceOf Int HashRef/;

use Medical::Growth;

extends 'PEDSnet::Derivation';
with 'MooX::Role::Chatty';

# Override default verbosity level - current MooX::Role::Chatty
# default silences warnings.
has '+verbose' => ( default => sub { -1; } );

=head1 NAME

PEDSnet::Derivation::Anthro_Z - Compute Z scores using Medical::Growth systems

=head1 DESCRIPTION

L<PEDSnet::Derivation::Anthro_Z> computes Z scores using measurement
systems based on L<Medical::Growth>.  Generally, one new measurement
record is created for each elibible input measurement.  Nearly all
other specifics are determined by settings in
L<PEDSnet::Derivation::Anthro_Z::Config>, or the implementation of the
L<Medical::Growth> system used.

Please note that L<PEDSnet::Derivation::Anthro_Z> will not populate
C<measurement_id> in the records it writes.  This allows for the
output table to populate it automaatically from a sequence or by a
similar mechanism.  If not, the application code will need to do so.

L<PEDSnet::Derivation::Anthro_Z> makes available the following methods:

=head2 Methods

=over 4

=cut

has '_pending_output' =>
  ( is => 'ro', required => 0, default => sub { [] });

=item get_measure_class(I<$selectors>)

Returns a handle for the measurement class found by
L<Medical::Growth/measure_class_for> using the contents of the hash
reference I<$selectors>.

The implementation here caches results for speed.

=cut

sub get_measure_class {
  my($self, $selectors) = @_;
  state $cache = {};
  my $key = join '|', %$selectors;
  $cache->{$key} //=
    eval { Medical::Growth->measure_class_for(%$selectors) };
}

=item compute_z(I<$selectors>, I<$value>, I<$args>)

Where I<$value> is a numeric measurement value (not a measurement
record), compute and return the Z score using the measurement class
found by L</get_measure_class> using I<$selectors>.  If present,
I<$args> is a reference to an array of additional arguments to be
passed after I<$value>.

=cut

sub compute_z {
  my($self, $selectors, $value, $args ) = @_;
  $args //= [];
  my $mc = $self->get_measure_class( $selectors );
  return unless $mc;
  $mc->z_for_value($value, @$args);
}

=item z_meas_for_person(I<$person_rec>, I<$meas_list>, I<$mc_map>)

For the person whose data are in I<$person_rec>, construct Z score
measurement records for each eligible measurement record in
I<$meas_list>, usng I<$mc_map> as the mapping between
C<measurement_concept_id>s and Z score derivations.  This
implementation is relatively specific to anthropometrics, in that it
is currently hard-coded to pass only the age as an index argument to
the C<z_for_value> function ultimately responsible for the
computation.

The hash reference to which I<$person_rec> points must at least
contain C<person_id>, and the person's date of birth, as one of
C<dt_of_birth> (a L<DateTime>), C<time_of_birth> (a string parseable
by L<Rose::DateTime::Util/parse_date>), or the base OMOP
C<year_of_birth>, C<month_of_birth>, and C<day_of_birth> numeric
values.  If C<dt_of_birth> wasn't already present, it will be added to
I<$person_rec> for efficienct on subsequent calls.

The I<$meas_list> argument must be an array reference, pointing to a
list of measurement records, each of which is a hash reference with
keys corresponding to the columns of the PEDSnet CDM C<measurement>
table.  The I<$mc_map> argument must also be an array reference
pointing to a list of has references as described in
L<PEDSnet::Derivation::Anthro_Z/concept_id_map>.

Returns a reference to a list of measurement records containing the Z
scores.  If either I<$meas_list> or I<$mc_map> is missing or empty,
returns nothing.

=cut

sub z_meas_for_person {
  my($self, $person, $meas, $cid_map) = @_;
  $cid_map //= $self->config->concept_id_map;
  my $conf = $self->config;
  my($z_map, $z_type_cid, $z_unit_cid, $z_unit_sv, $clone) =
    ($conf->concept_id_map,
     $conf->z_measurement_type_concept_id,
     $conf->z_unit_concept_id,
     $conf->z_unit_source_value,
     $conf->clone_z_measurements);
  my $verbose = $self->verbose;
  my(@z_scores, @clone_except);

  return unless $meas and @$meas and $cid_map and @$cid_map;

  @clone_except = $conf->clone_attributes_except->@* if $clone;

  $person->{dt_of_birth} //=
    parse_date($person->{time_of_birth} //
	       join('-', map { $person->{$_} } qw/ year_of_birth
						   month_of_birth
						   day_of_birth /))
    unless exists $person->{dt_of_birth};

  foreach my $pair ($cid_map->@*) {
    my $meas_cid = $pair->{measurement_concept_id};
    my $z_info = $pair->{z_score_info};
    
    foreach my $m (grep { $_->{measurement_concept_id} == $meas_cid} @$meas) {

      # Can't compute Z score for raw measure of 0
      next unless $m->{value_as_number};
      
      $m->{measurement_dt} =
	parse_date($m->{measurement_time} // $m->{measurement_date})
	unless exists $m->{measurement_dt};

      if (exists $z_info->{z_check_callback}) {
	next unless $z_info->{z_check_callback}->($person, $m, $pair);
      }

      my %age = $m->{measurement_dt}->delta_md($person->{dt_of_birth})->deltas;
      my $age_mo = $age{months} + $age{days} / 31;
      my $z_val = $self->compute_z({ system => $z_info->{z_class_system},
				     measure => $z_info->{z_class_measure},
				     age_group => ($age_mo < 24
						   ? 'Infant' : 'Child'),
				     sex => lc $person->{gender_name} },
				   $m->{value_as_number}, [ $age_mo ]);
      $self->remark( sprintf 'Computed %s Z score %4.2f for meas %d on %s',
		     $z_info->{z_class_measure}, $z_val,
		     $m->{measurement_id}, $m->{measurement_time})
	if $verbose >= 3;

      next if !defined($z_val) or $z_val =~ /Inf/;
      
      if ($clone) { 
	my $z_rec = { %$m };
	delete $z_rec->{$_} for @clone_except;
	$z_rec->{measurement_concept_id} = $z_info->{z_measurement_concept_id},
	$z_rec->{measurement_type_concept_id} = $z_type_cid;
	$z_rec->{value_as_number} = $z_val;
	$z_rec->{operator_concept_id} ||= 4172703;
	$z_rec->{unit_concept_id} = $z_unit_cid;
	$z_rec->{unit_source_value} = $z_unit_sv;
	$z_rec->{measurement_source_value} =
	  "PEDSnet NHANES 2000 Z score computation v$VERSION";
	$z_rec->{measurement_source_concept_id} = 0;
	$z_rec->{value_source_value} = "measurement: $m->{measurement_id}";
	push @z_scores, $z_rec;
      }
      else {
	my $z_rec = 
	  {
	   person_id => $m->{person_id},
	   measurement_concept_id => $z_info->{z_measurement_concept_id},
	   measurement_date => $m->{measurement_date},
	   measurement_time => $m->{measurement_time},
	   measurement_type_concept_id => $z_type_cid,
	   value_as_number => $z_val,
	   operator_concept_id => $m->{operator_concept_id} || 4172703,
	   unit_concept_id => $z_unit_cid,
	   unit_source_value => $z_unit_sv,
	   measurement_source_value =>
	     "PEDSnet NHANES 2000 Z score computation v$VERSION",
	   measurement_source_concept_id => 0,
	   value_source_value => "measurement: $m->{measurement_id}"
	};
	# Optional keys - should be there but may be skipped if input
	# was not read from measurement table
	foreach my $k (qw/ measurement_result_date measurement_result_time
			   provider_id visit_occurrence_id site /) {
	  $z_rec->{$k} = $m->{$k} if exists $m->{$k};
	}
	push @z_scores, $z_rec;
      }
    }
  }

  \@z_scores;
}

=item get_meas_for_person_qry

Returns a L<Rose::DBx::CannedQuery::Glycosylated> prepared to retrieve
from the source backend measurement records for the C<person_id>
passed as a bind parameter value when executing the query.

This implementation will construct the query to retrieve all records
from L<PEDSnet::Derivation::Anthro_Z/input_measurement_table> whose
C<person_id> matches the bind parameter value and
C<measurement_concept_id> matches one of the IDs in
L<PEDSnet::Derivation::Anthro_Z/concept_id_map>.

=cut

sub get_meas_for_person_qry {
  my $self = shift;
  my $config = $self->config;
  
  $self->src_backend->
    get_query(q[SELECT * FROM ] . $config->input_measurement_table .
              q[ WHERE measurement_concept_id IN (] .
	      join(', ', map { $_->{measurement_concept_id} }
		   $config->concept_id_map->@*) . q[)
              AND person_id = ?]);
}

=item save_meas_qry($rows_to_save)

Returns a L<Rose::DBx::CannedQuery::Glycosylated> object containing a
query that will save to the sink backend I<$chunk_size> measurement
records.  The query will expect values for the measurement records as
bind parameter values.

=cut

# TODO: Refactor into base class
sub save_meas_qry {
  my( $self, $chunk_size ) = @_;
  my $sink = $self->sink_backend;
  my $tab = $self->config->output_measurement_table;
  my $full_chunk = $self->config->output_chunk_size;
  state $cols = [ grep { $_ ne 'measurement_id' }
		  $sink->column_names($tab) ];
  my $sql = qq[INSERT INTO $tab (] . join(',', @$cols) .
            q[) VALUES ] .
	    join(',',
		 ('(' . join(',', ('?') x scalar @$cols) . ')') x $chunk_size);

  # Cache only "full-sized" version of query
  if ($chunk_size == $self->config->output_chunk_size) {
    return shift->sink_backend->get_query($sql);
  }
  else {
    return shift->sink_backend->build_query($sql);
  }
}

sub _save_zs {
  my( $self, $z_list) = @_;
  my $pending = $self->_pending_output;
  state $chunk_size = $self->config->output_chunk_size;

  push @$pending, @$z_list;
  
  while (@$pending > $chunk_size) {
    $self->sink_backend->store_chunk($self->save_meas_qry($chunk_size),
				     [ splice @$pending, 0, $chunk_size ]);
  }
  return scalar @$z_list;
}

=item flush_output

Flush any pending output records to the sink backend.  In most cases,
this is done for you automatically, but the method is public in case a
subclass or application wants to flush manually in circumstances where
it feels it's warranted.

=cut

# TODO: Refactor into base class
sub flush_output {
  my $self = shift;
  my $pending = $self->_pending_output;
  if (@$pending) {
    $self->sink_backend->store_chunk($self->save_meas_qry(scalar @$pending),
				     $pending);
    @$pending = ();
  }
}


=for Pod::Coverage DEMOLISH

=cut

sub DEMOLISH { shift->flush_output }

# TODO: Refactor into base class
has '_person_qry' => ( isa => InstanceOf['Rose::DBx::CannedQuery'], is => 'rwp',
		       lazy => 1, builder => '_build_person_qry');

# _get_person_qry
# Returns an active and executed L<Rose::DBx::CannedQuery> object used
# for fetching person records.  If any arguments are present, they are
# passed to the query as bind parameter values for execution.
#
# Returns nothing if the query could not be constructed or executed.
#
# This exists as a separate method only to provide a means to get bind
# parameters to the query, which a standard builder method cannot
# accommodate. If you need to use bind parameters, you have to call
# _get_person_qry yourself and pass the result to the
# PEDSnet::Derivation::BMI constructor as the value of _person_qry.
# If you can avoid this, consider it.  If you can't, consider wrapping
# the constructor in a method that does this bookkeeping, so the user
# doesn't need to.

sub _get_person_qry {
  my $self = shift;
  my $pt_qry = $self->src_backend->build_query($self->config->person_finder_sql);
  return unless $pt_qry && $pt_qry->execute(@_);

  $pt_qry;
}

sub _build_person_qry { shift->_get_person_qry; }

=item get_person_chunk($chunk)

Returns a reference to an array of person records.  If I<$chunk> is
present, specifies the desired number of records.  If it's not,
defaults to L<PEDSnet::Derivation::Anthro_Z::Config/person_chunk_size>.

This implementation fetches records as specified by
L<PEDSnet::Derivation::Anthro_Z::Config/person_finder_sql>.  You are
free to override this behavior in a subclass.  In particular, if you
want to parallelize computation over a large source database,
L</get_person_chunk> and
L<PEDSnet::Derivation::Anthro_Z::Config/person_finder_sql> give you
opportunities to point each process at a subset of persons.

=cut

#TODO: Refactor into base class
sub get_person_chunk {
  my $self = shift;
  my $qry = $self->_person_qry;
  my $chunk_size =  $self->config->person_chunk_size;
  my $chunk =
    $self->src_backend->fetch_chunk($self->_person_qry, $chunk_size);

  # This ridiculous aside because DBD::CSV/SQL::Statement keeps
  # the table alias in the key name and chokes if you try to
  # provide attribute aliases in the query
  if (@$chunk and join('', keys %{$chunk->[0]}) =~ /\./) {
    my(@replace);
    foreach my $k (keys %{ $chunk->[0]}) {
      next unless $k =~ /\./;
      my $nk = $k =~ s/.+\.//r;
      push @replace, [ $k, $nk ];
    }

    foreach my $pair (@replace) {
      my($k, $nk) = @$pair;
      map { $_->{$nk} = $_->{$k}; delete $_->{$k} } @$chunk;
    }
  }

  $chunk;
}

=item process_person_chunk($persons)

For each person record in the list referred to by I<$persons>, compute
Z scores from measurement data in the source backend, and save results
to the sink backend.  A person record is a hash reference, as
described above in L</z_meas_for_person>.

Returns the number of Z score records saved in scalar context, or in list
context the number of Z score records saved followed by the number of
persons having at least one Z score record saved.

=cut

# TODO: Refactor out into base class
sub process_person_chunk {
  my( $self, $person_list ) = @_;
  my $get_qry = $self->get_meas_for_person_qry;
  my $src = $self->src_backend;
  my $saved_rec = 0;
  my(%saved_pers);

  foreach my $p ($person_list->@*) {
    next unless $src->execute($get_qry, [ $p->{person_id} ]);
    my(@anthro);

    # Wrap into one go, since rare for a single patient to have a huge
    # number of input measurements
    while (my @rows = $src->fetch_chunk($get_qry)->@*) { push @anthro, @rows }
    
    if (my $zs = $self->z_meas_for_person($p, \@anthro)) {
      $saved_pers{ $p->{person_id} }++;
      $saved_rec += $self->_save_zs($zs);
    }
  }

  return ($saved_rec, scalar keys %saved_pers) if wantarray;
  return $saved_rec;
}

=item generate_zs()

Using data from the L<PEDSnet::Derivation/config> attribute, compute
Z scores for everyone.

In scalar context, returns the number of records saved.  In list
contest returns the number of records and the number of unique
persons with at least one record derived.

=cut

sub generate_zs {
  my $self = shift;
  my $src = $self->src_backend;
  my $config = $self->config;
  my($saved_rec, $saved_pers) = (0,0);
  my $chunk_size =  $config->person_chunk_size;
  my $verbose = $self->verbose;
  my($chunk);

  $self->remark("Finding patients with measurements") if $verbose;
  return unless $self->_get_person_qry;

  $self->remark("Starting computation") if $verbose;
  while ($chunk = $self->get_person_chunk and @$chunk) {
    my($rec_ct, $pers_ct) = $self->process_person_chunk($chunk);
    $saved_rec += $rec_ct;
    $saved_pers += $pers_ct;
    $self->remark([ 'Completed %d persons/%d records (total %d/%d)',
		    $pers_ct, $rec_ct, $saved_pers, $saved_rec ])
      if $self->verbose;
  }

  $self->flush_output;

  $self->remark("Done") if $self->verbose;
  
  return ($saved_rec, $saved_pers) if wantarray;
  return $saved_rec;
  
}


1;

__END__

=back

=head1 BUGS AND CAVEATS

Are there, for certain, but have yet to be cataloged.

=head1 VERSION

version 0.04

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
