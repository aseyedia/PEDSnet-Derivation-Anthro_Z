
use strict;
use warnings;

use Module::Build 0.28;


my %module_build_args = (
  "build_requires" => {
    "Module::Build" => "0.28"
  },
  "configure_requires" => {
    "ExtUtils::MakeMaker" => 0,
    "Module::Build" => "0.28"
  },
  "dist_abstract" => "Compute Z scores using Medical::Growth systems",
  "dist_author" => [
    "Charles Bailey <cbail\@cpan.org>"
  ],
  "dist_name" => "PEDSnet-Derivation-Anthro_Z",
  "dist_version" => "0.04",
  "license" => "open_source",
  "module_name" => "PEDSnet::Derivation::Anthro_Z",
  "recursive_test_files" => 1,
  "requires" => {
    "Getopt::Long" => 0,
    "Medical::Growth" => 0,
    "Moo" => 2,
    "MooX::Role::Chatty" => 0,
    "PEDSnet::Derivation" => 0,
    "PEDSnet::Derivation::Backend::RDB" => 0,
    "PEDSnet::Derivation::Config" => 0,
    "Path::Tiny" => 0,
    "Pod::Usage" => 0,
    "Rose::DateTime::Util" => 0,
    "Scalar::Util" => 0,
    "Types::Standard" => 0,
    "perl" => "5.024",
    "strict" => 0,
    "warnings" => 0
  },
  "script_files" => [
    "script/anthro_z_sample.conf",
    "script/derive_z"
  ],
  "test_requires" => {
    "DBD::SQLite" => 0,
    "ExtUtils::MakeMaker" => 0,
    "File::Spec" => 0,
    "FindBin" => 0,
    "PEDSnet::Derivation::Backend::CSV" => 0,
    "Rose::DB" => 0,
    "Test::Differences" => 0,
    "Test::More" => 0,
    "parent" => 0
  }
);


my %fallback_build_requires = (
  "DBD::SQLite" => 0,
  "ExtUtils::MakeMaker" => 0,
  "File::Spec" => 0,
  "FindBin" => 0,
  "Module::Build" => "0.28",
  "PEDSnet::Derivation::Backend::CSV" => 0,
  "Rose::DB" => 0,
  "Test::Differences" => 0,
  "Test::More" => 0,
  "parent" => 0
);


unless ( eval { Module::Build->VERSION(0.4004) } ) {
  delete $module_build_args{test_requires};
  $module_build_args{build_requires} = \%fallback_build_requires;
}

my $build = Module::Build->new(%module_build_args);


$build->create_build_script;
