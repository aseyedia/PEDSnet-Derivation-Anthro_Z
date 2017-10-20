#!/usr/bin/env perl
#
# We need to test patient_list_qry separately because the syntax is
# beyond DBD::CSV. 

use strict;
use warnings;

use Test::More;

my $has_sqlite = eval { require DBD::SQLite };

if ($has_sqlite) {
  ### Test RDB class using in-core scratch db
  package My::Test::RDB;
  require FindBin;
  require Path::Tiny;
  
  use parent 'Rose::DB';

  my $db =
    Path::Tiny::path('person_qry_test.db')->absolute($FindBin::Bin)->canonpath;

  __PACKAGE__->use_private_registry;

  __PACKAGE__->register_db( domain   => 'test',
			    type     => 'vapor',
			    driver   => 'SQLite',
			    database => $db,
			  );

  package main;

  ### Set up the test environment
  my $rdb = My::Test::RDB->new(connect_options => { RaiseError => 1 },
			       domain          => 'test',
			       type            => 'vapor');

  require PEDSnet::Derivation::Backend::RDB;
  require PEDSnet::Derivation::Anthro_Z;
  require PEDSnet::Derivation::Anthro_Z::Config;

  my $backend = PEDSnet::Derivation::Backend::RDB->new(rdb => $rdb);
  my $config = PEDSnet::Derivation::Anthro_Z::Config->
    new(config_stems => [ Path::Tiny::path('person_list')->
			  absolute($FindBin::Bin)->canonpath ]);
  my $handle = PEDSnet::Derivation::Anthro_Z->new(src_backend => $backend,
						  sink_backend => $backend,
						  config => $config);

  my $got_sql = lc $handle->config->person_finder_sql =~ s/\s+|\n//gr;
  my $want_sql = lc
    q[select distinct p.person_id, p.birth_datetime,
                         c.concept_name as gender_name
      from person_list_input m
      inner join person_demo p on p.person_id = m.person_id
      left join concept c ON c.concept_id = p.gender_concept_id
      where m.measurement_concept_id in (3023540,3013762,3038553)]
    =~ s/\s+|\n//gr;
  is($got_sql, $want_sql, 'Default person finder SQL - full');

  my $plist = eval { $handle->get_person_chunk };
  is(scalar @$plist, 3, 'Patient count');
  is_deeply( [ grep { $_->{person_id} == 2 } @$plist ],
	     [ { person_id => 2,
	       birth_datetime => '2000-06-18T00:00:00',
	       gender_name => 'MALE' } ],
	     'Result contents');

  $config = PEDSnet::Derivation::Anthro_Z::Config->
    new(config_stems => [ Path::Tiny::path('anthro_z')->
			  absolute($FindBin::Bin)->canonpath ]);
  is($config->sql_flavor, 'limited', 'Default to limited SQL flavor');

  $got_sql = lc $config->person_finder_sql =~ s/\s+|\n//gr;
  $want_sql = lc
    q[select distinct p.person_id, p.birth_datetime,
                         c.concept_name as gender_name
      from person as p, measurement as m, concept as c
      where p.person_id = m.person_id 
            and p.gender_concept_id = c.concept_id
           and m.measurement_concept_id in (3023540,3013762,3038553,3001537)]
    =~ s/\s+|\n//gr;
  is($got_sql, $want_sql, 'Default person finder SQL - limited');

  $config = PEDSnet::Derivation::Anthro_Z::Config->
    new(config_stems => [ Path::Tiny::path('anthro_z_less')->
			  absolute($FindBin::Bin)->canonpath ]);
  is($config->person_finder_sql,
     "select data from somewhere where it = 'good';",
     'Custom person finder SQL');

}

done_testing;
