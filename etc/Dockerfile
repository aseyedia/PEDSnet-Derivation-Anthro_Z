# Minimal Dockerfile for PEDSnet::Derivation::Anthro_Z build, using
# standard Perl image as base
#
# To set up, just pick the build option you want below, then say
#   docker build -t PEDSnet-Derivation-Anthro_Z -f /path/to/this/file
#
# Once built, you can run with access to files in /your/data/dir
# by saying
#   docker run -v /your/data/dir:/working --rm -it PEDSnet-Derivation-Anthro_Z

FROM perl:latest
LABEL description "Simple image for PEDSnet::Derivation::Anthro_Z"
LABEL maintainer "Charles Bailey <baileyc@email.chop.edu>"

# Build using the current version on GitHub
RUN cpanm git://github.com/PEDSnet/PEDSnet-Derivation
RUN cpanm git://github.com/PEDSnet/PEDSnet-Derivation-Anthro_Z

# Build using released version of PEDSnet::Derivation
#RUN cpanm PEDSnet::Derivation::Anthro_Z

# Alternatively, to install local copy, first say
#   dzil build
# then build using local version (Remember that you'll
# need to do the same for PEDSnet::Derivation if you want
# to use a non-CPAN version)
#COPY PEDSnet-Derivation-Anthro_Z-*.tar.gz /src/
#RUN cpanm /src/*.tar.gz


RUN useradd -m -s /bin/bash normalized
USER normalized
WORKDIR /working
CMD /bin/bash
