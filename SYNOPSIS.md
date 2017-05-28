# NAME

PEDSnet::Derivation::Anthro\_Z - Compute Z scores using Medical::Growth systems

# DESCRIPTION

[PEDSnet::Derivation::Anthro\_Z](https://metacpan.org/pod/PEDSnet::Derivation::Anthro_Z) computes Z scores using measurement
systems based on [Medical::Growth](https://metacpan.org/pod/Medical::Growth).  Generally, one new measurement
record is created for each elibible input measurement.  Nearly all
other specifics are determined by settings in
[PEDSnet::Derivation::Anthro\_Z::Config](https://metacpan.org/pod/PEDSnet::Derivation::Anthro_Z::Config), or the implementation of the
[Medical::Growth](https://metacpan.org/pod/Medical::Growth) system used.

Please note that [PEDSnet::Derivation::Anthro\_Z](https://metacpan.org/pod/PEDSnet::Derivation::Anthro_Z) will not populate
`measurement_id` in the records it writes.  This allows for the
output table to populate it automaatically from a sequence or by a
similar mechanism.  If not, the application code will need to do so.

[PEDSnet::Derivation::Anthro\_Z](https://metacpan.org/pod/PEDSnet::Derivation::Anthro_Z) makes available the following methods:

## Methods

- get\_measure\_class(_$selectors_)

    Returns a handle for the measurement class found by
    ["measure\_class\_for" in Medical::Growth](https://metacpan.org/pod/Medical::Growth#measure_class_for) using the contents of the hash
    reference _$selectors_.

    The implementation here caches results for speed.

- compute\_z(_$selectors_, _$value_, _$args_)

    Where _$value_ is a numeric measurement value (not a measurement
    record), compute and return the Z score using the measurement class
    found by ["get\_measure\_class"](#get_measure_class) using _$selectors_.  If present,
    _$args_ is a reference to an array of additional arguments to be
    passed after _$value_.

- z\_meas\_for\_person(_$person\_rec_, _$meas\_list_, _$mc\_map_)

    For the person whose data are in _$person\_rec_, construct Z score
    measurement records for each eligible measurement record in
    _$meas\_list_, usng _$mc\_map_ as the mapping between
    `measurement_concept_id`s and Z score derivations.  This
    implementation is relatively specific to anthropometrics, in that it
    is currently hard-coded to pass only the age as an index argument to
    the `z_for_value` function ultimately responsible for the
    computation.

    The hash reference to which _$person\_rec_ points must at least
    contain `person_id`, and the person's date of birth, as one of
    `dt_of_birth` (a [DateTime](https://metacpan.org/pod/DateTime)), `time_of_birth` (a string parseable
    by ["parse\_date" in Rose::DateTime::Util](https://metacpan.org/pod/Rose::DateTime::Util#parse_date)), or the base OMOP
    `year_of_birth`, `month_of_birth`, and `day_of_birth` numeric
    values.  If `dt_of_birth` wasn't already present, it will be added to
    _$person\_rec_ for efficienct on subsequent calls.

    The _$meas\_list_ argument must be an array reference, pointing to a
    list of measurement records, each of which is a hash reference with
    keys corresponding to the columns of the PEDSnet CDM `measurement`
    table.  The _$mc\_map_ argument must also be an array reference
    pointing to a list of has references as described in
    ["concept\_id\_map" in PEDSnet::Derivation::Anthro\_Z](https://metacpan.org/pod/PEDSnet::Derivation::Anthro_Z#concept_id_map).

    Returns a reference to a list of measurement records containing the Z
    scores.  If either _$meas\_list_ or _$mc\_map_ is missing or empty,
    returns nothing.

- get\_meas\_for\_person\_qry

    Returns a [Rose::DBx::CannedQuery::Glycosylated](https://metacpan.org/pod/Rose::DBx::CannedQuery::Glycosylated) prepared to retrieve
    from the source backend measurement records for the `person_id`
    passed as a bind parameter value when executing the query.

    This implementation will construct the query to retrieve all records
    from ["input\_measurement\_table" in PEDSnet::Derivation::Anthro\_Z](https://metacpan.org/pod/PEDSnet::Derivation::Anthro_Z#input_measurement_table) whose
    `person_id` matches the bind parameter value and
    `measurement_concept_id` matches one of the IDs in
    ["concept\_id\_map" in PEDSnet::Derivation::Anthro\_Z](https://metacpan.org/pod/PEDSnet::Derivation::Anthro_Z#concept_id_map).

- save\_meas\_qry($rows\_to\_save)

    Returns a [Rose::DBx::CannedQuery::Glycosylated](https://metacpan.org/pod/Rose::DBx::CannedQuery::Glycosylated) object containing a
    query that will save to the sink backend _$chunk\_size_ measurement
    records.  The query will expect values for the measurement records as
    bind parameter values.

- flush\_output

    Flush any pending output records to the sink backend.  In most cases,
    this is done for you automatically, but the method is public in case a
    subclass or application wants to flush manually in circumstances where
    it feels it's warranted.

- get\_person\_chunk($chunk)

    Returns a reference to an array of person records.  If _$chunk_ is
    present, specifies the desired number of records.  If it's not,
    defaults to ["person\_chunk\_size" in PEDSnet::Derivation::Anthro\_Z::Config](https://metacpan.org/pod/PEDSnet::Derivation::Anthro_Z::Config#person_chunk_size).

    This implementation fetches records as specified by
    ["person\_finder\_sql" in PEDSnet::Derivation::Anthro\_Z::Config](https://metacpan.org/pod/PEDSnet::Derivation::Anthro_Z::Config#person_finder_sql).  You are
    free to override this behavior in a subclass.  In particular, if you
    want to parallelize computation over a large source database,
    ["get\_person\_chunk"](#get_person_chunk) and
    ["person\_finder\_sql" in PEDSnet::Derivation::Anthro\_Z::Config](https://metacpan.org/pod/PEDSnet::Derivation::Anthro_Z::Config#person_finder_sql) give you
    opportunities to point each process at a subset of persons.

- process\_person\_chunk($persons)

    For each person record in the list referred to by _$persons_, compute
    Z scores from measurement data in the source backend, and save results
    to the sink backend.  A person record is a hash reference, as
    described above in ["z\_meas\_for\_person"](#z_meas_for_person).

    Returns the number of Z score records saved in scalar context, or in list
    context the number of Z score records saved followed by the number of
    persons having at least one Z score record saved.

- generate\_zs()

    Using data from the ["config" in PEDSnet::Derivation](https://metacpan.org/pod/PEDSnet::Derivation#config) attribute, compute
    Z scores for everyone.

    In scalar context, returns the number of records saved.  In list
    contest returns the number of records and the number of unique
    persons with at least one record derived.

# BUGS AND CAVEATS

Are there, for certain, but have yet to be cataloged.

# VERSION

version 0.04

# AUTHOR

Charles Bailey <cbail@cpan.org>

# COPYRIGHT AND LICENSE

Copyright (C) 2016 by Charles Bailey

This software may be used under the terms of the Artistic License or
the GNU General Public License, as the user prefers.

This code was written at the Children's Hospital of Philadelphia as
part of [PCORI](http://www.pcori.org)-funded work in the
[PEDSnet](http://www.pedsnet.org) Data Coordinating Center.
