#!/usr/bin/env perl


use 5.024;
use strict;
use warnings;

use Test::More;


my $has_sqlite = eval { require DBD::SQLite };
my $rdb;

if ($has_sqlite) {
  ### Test RDB class using in-core scratch db
  package My::Test::RDB;
  
  use parent 'Rose::DB';

  __PACKAGE__->use_private_registry;

  __PACKAGE__->register_db( domain   => 'test',
			    type     => 'vapor',
			    driver   => 'SQLite',
			    database => ':memory:',
			  );

  # SQLite in-memory db evaporates when original dbh is closed.
  sub dbi_connect {
    my( $self, @args ) = @_;
    state $dbh = $self->SUPER::dbi_connect(@args);
    $dbh;
  }


  package main;

  ### Set up the test environment
  $rdb = new_ok( 'My::Test::RDB' => [ connect_options => { RaiseError => 1 },
				      domain          => 'test',
				      type            => 'vapor'
				    ],
		    'Setup test db'
		  );
  my $dbh = $rdb->dbh;

  $dbh->do('create table concept
            (concept_id integer primary key,
             concept_name varchar(16),
             standard_concept varchar(1),
             concept_class_id varchar(16) )');
  # N.B. concept_id deliberately wrong
  $dbh->do(q[insert into concept values (45754908, 'Derived value', 'S', 'Meas Type')]);

}

require_ok('PEDSnet::Derivation::Anthro_Z::Config');

my $config = new_ok('PEDSnet::Derivation::Anthro_Z::Config');

my $x = $config->concept_id_map;

foreach my $c ( [ z_measurement_type_concept_id => 45754907 ],
		[ z_unit_concept_id => 0 ],
		[ z_unit_source_value => 'SD' ],
		[ input_person_table => 'person' ],
		[ input_measurement_table => 'measurement' ],
		[ output_measurement_table => 'measurement' ],
		[ clone_z_measurements => 0 ],
		[ output_chunk_size => 1000 ],
		[ person_chunk_size => 1000 ],
	      ) {
  my $meth = $c->[0];
  cmp_ok($config->$meth,
	 ($c->[1] =~ /^\d+$/ ? '==' : 'eq'),
	 $c->[1], "Value for $c->[0]");
}

is_deeply($config->clone_attributes_except,
	  [ qw/ measurement_id special_attr measurement_dt / ],
	  'Value for clone_attributes_except');

is_deeply($config->concept_id_map,
	  [ { measurement_concept_id => 3023540,
	      z_score_info => {
			       z_class_measure => "Height for Age",
			       z_measurement_concept_id => 2000000042
			      }
	    },
	    {
	     measurement_concept_id => 3013762,
	     z_score_info => {
			      z_class_measure => "Weight for Age",
			      z_measurement_concept_id => 2000000041
			     }
	    },
	    {
	     measurement_concept_id => 3038553,
	     z_score_info => {
			      z_class_measure => "BMI for Age",
			      z_measurement_concept_id => 2000000043
			     }
	    },
	    {
	     measurement_concept_id => 3001537,
	     z_score_info => {
			      z_class_measure => "HC for Age",
			      z_measurement_concept_id => 2000000999
			     }
	    },
	  ],
	 'Value for config_id_map');

if ($has_sqlite) {
  $config = PEDSnet::Derivation::Anthro_Z::Config->
    new( config_stems => [ 'z_less' ], config_rdb => $rdb);
  cmp_ok($config->z_measurement_type_concept_id, '==', 45754908,
	 'Value for z_measurement_type_concept_id (via db)');
}

done_testing;
