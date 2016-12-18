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
  my $pq = eval {$handle->person_list_qry };
  my $error = $@;

  is($error, '', 'Create patient list query');
  isa_ok($pq, 'Rose::DBx::CannedQuery', 'Retrieved query');

  my $plist = eval { $pq->execute->fetchall_arrayref({}) };
  is(scalar @$plist, 3, 'Patient count');
  is_deeply( [ grep { $_->{person_id} == 2 } @$plist ],
	     [ { person_id => 2,
	       time_of_birth => '2000-06-18T00:00:00',
	       gender_name => 'MALE' } ],
	     'Result contents');
}

done_testing;
