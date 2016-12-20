#!perl
#
# $Id$

use 5.024;
use strict;
use warnings;

package PEDSnet::Derivation::Anthro_Z;

our($VERSION) = '0.03';
our($REVISION) = '$Revision$' =~ /: (\d+)/ ? $1 : 0;

use Moo 2;

use Rose::DateTime::Util qw( parse_date );
use Types::Standard qw/InstanceOf Int HashRef/;

use Medical::Growth::NHANES_2000;

extends 'PEDSnet::Derivation';
with 'MooX::Role::Chatty';

has '_pending_output' =>
  ( is => 'ro', required => 0, default => sub { [] });

sub get_measure_class {
  my($self, %selectors) = @_;
  state $cache = {};
  my $key = join '|', %selectors;
  $cache->{$key} //=
    eval { Medical::Growth::NHANES_2000->measure_class_for(%selectors) };
}

sub compute_z {
  my($self, $type, $sex, $age, $value ) = @_;
  $self->get_measure_class( sex => $sex,
			    age_group => $age,
			    measure => $type )->z_for_value($value, $age);
}


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

  return unless $cid_map and @$cid_map;

  @clone_except = $conf->clone_attributes_except->@* if $clone;

  $person->{dt_of_birth} =
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
      my %age = $m->{measurement_dt}->delta_md($person->{dt_of_birth})->deltas;
      my $age_mo = $age{months} + $age{days} / 31;
      my $mc =
	$self->get_measure_class( measure => $z_info->{z_class_measure},
				  age_group => ($age_mo < 24
						? 'Infant' : 'Child'),
				  sex => lc $person->{gender_name} );
      next unless $mc;
      my $z_val = $mc->z_for_value($m->{value_as_number}, $age_mo);

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
	$z_rec->{value_source_value} =
	  "person: $person->{person_id}, measurement: $m->{measurement_id}";
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
	   value_source_value =>
	     "person: $person->{person_id}, measurement: $m->{measurement_id}"
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

=cut

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

sub flush_output {
  my $self = shift;
  my $pending = $self->_pending_output;
  if (@$pending) {
    $self->sink_backend->store_chunk($self->save_meas_qry(scalar @$pending),
				     $pending);
    @$pending = ();
  }
}

sub DEMOLISH { shift->flush_output }

=item process_person_chunk($persons)

=cut

sub process_person_chunk {
  my( $self, $person_list ) = @_;
  my $get_qry = $self->get_meas_for_person_qry;
  my $src = $self->src_backend;
  my $saved = 0;

  foreach my $p ($person_list->@*) {
    next unless $src->execute($get_qry, [ $p->{person_id} ]);
    my(@anthro);

    # Wrap into one go, since rare for a single patient to have a huge
    # number of input measurements
    while (my @rows = $src->fetch_chunk($get_qry)->@*) { push @anthro, @rows }
    
    $saved += $self->_save_zs($self->z_meas_for_person($p, \@anthro));

  }

  $saved;
}


sub person_list_qry {
  my($self) = @_;
  my $src = $self->src_backend;
  my $config = $self->config;

  # DBD::CSV has a hard time with explicit 3-table join
  if (ref($src) =~ /:CSV/) {
    my $ptab = $config->input_person_table;
    $src->build_query(qq[SELECT DISTINCT person_id,
                              time_of_birth,
                              c.concept_name AS gender_name
                         FROM ] . $config->input_person_table . q[ AS p,
                         ] . $config->input_measurement_table . q[ AS m,
		         concept AS c
			 WHERE p.person_id = m.person_id 
                         AND p.gender_concept_id = c.concept_id
                         AND m.measurement_concept_id IN (] .
	  	      join(', ', map { $_->{measurement_concept_id} }
  		  	   $self->config->concept_id_map->@*) . q[)]);
  }
  else {
    $src->build_query(q[SELECT DISTINCT p.person_id, p.time_of_birth,
                            c.concept_name as gender_name
                        FROM ] . $config->input_measurement_table . q[ m
                        INNER JOIN ] . $config->input_person_table .
	  	            q[ p on p.person_id = m.person_id
                        LEFT JOIN concept c ON c.concept_id = p.gender_concept_id
                        WHERE m.measurement_concept_id IN (] . 
	  	      join(', ', map { $_->{measurement_concept_id} }
  		  	   $self->config->concept_id_map->@*) . q[)]);
  }
}

sub generate_zs {
  my $self = shift;
  my $src = $self->src_backend;
  my $config = $self->config;
  my($saved_rec, $saved_pers) = (0,0);
  my $chunk_size =  $config->person_chunk_size;
  my $verbose = $self->verbose;
  my($pt_qry, $chunk);

  $self->remark("Finding patients with measurements") if $verbose;
  $pt_qry = $self->person_list_qry;
  return unless $pt_qry->execute;

  $self->remark("Starting computation") if $verbose;
  while ($chunk = $src->fetch_chunk($pt_qry, $chunk_size) and @$chunk) {
    my $ct = $self->process_person_chunk($chunk);
    $saved_rec += $ct;
    $saved_pers += scalar @$chunk;
    $self->remark([ 'Completed %d persons/%d records (total %d/%d)',
		    scalar @$chunk, $ct, $saved_pers, $saved_rec ])
      if $self->verbose;
  }

  $self->flush_output;

  $self->remark("Done") if $self->verbose;
  
  return ($saved_rec, $saved_pers) if wantarray;
  return $saved_rec;
  
}


1;

__END__

=head1 NAME

PEDSnet::Derivation::Anthro_Z - blah blah blah

=head1 SYNOPSIS

  use PEDSnet::Derivation::Anthro_Z;
  blah blah blah

=head1 DESCRIPTION

Blah blah blah.

The following command line options are available:

=head1 OPTIONS

=over 4

=item B<--help>

Output a brief help message, then exit.

=item B<--man>

Output this documentation, then exit.

=item B<--version>

Output the program version, then exit.

=back

=head1 USE AS A MODULE

Is encouraged.  This file can be included in a larger program using
Perl's L<require> function.  It provides the following functions in the
package B<Foo>:

=head2 FUNCTIONS

It helps to document these if you encourage use as a module.

=over 4

=back

=head2 EXPORT

None by default.

=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 DIAGNOSTICS

Any message produced by an included package, as well as

=over 4

=item B<EANY>

Anything went wrong.

=item B<Something to say here>

A warning that something newsworthy happened.

=back

=head1 BUGS AND CAVEATS

Are there, for certain, but have yet to be cataloged.

=head1 VERSION

version 0.01

=head1 AUTHOR

Charles Bailey <cbail@cpan.org>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2015 by Charles Bailey

This software may be used under the terms of the Artistic License or
the GNU General Public License, as the user prefers.

=cut
