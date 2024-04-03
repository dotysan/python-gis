# TODO: add dockerfile version here; require BuildKit
ARG HERE=https://github.com/dotysan/python-gis

ARG PYVER=3.11
ARG GDVER=3.8.4
ARG NPVER=1.26.*
ARG FIONAVER=1.9.*

# ARG TDBVER=2.19.1
# ARG TDBREF=29ceb3e7

ARG DEBVER=bookworm
ARG FFREF=6652531122d8ee34e9b926c8a110ab1892d6382c
#======================================================================
FROM debian:$DEBVER AS build-ffmpeg

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get upgrade --yes

# dependencies for fetching & building ffmpeg-static
RUN apt-get install --yes --no-install-recommends \
    bzip2 \
    ca-certificates \
    g++ \
    git \
    make \
    patch \
    pkgconf \
    wget

ARG FFREF
RUN git clone --depth 1 --branch fireview --single-branch \
    https://github.com/dotysan/ffmpeg-static && \
    cd ffmpeg-static && git fetch --depth 1 origin $FFREF \
    && git checkout FETCH_HEAD

WORKDIR /ffmpeg-static

RUN ./build.sh nasm
RUN ./build.sh x264
RUN ./build.sh ffmpeg

RUN find build \( -name ffmpeg -o -name ffprobe \) \
    -type f |xargs cp --target-directory /usr/local/bin
RUN ./ffinfo.sh |tee /ffinfo.txt

#======================================================================
ARG PYVER
ARG DEBVER
FROM python:$PYVER-$DEBVER as build-gdal

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get upgrade --yes

# needed for bootstrap; good to keep around too
RUN apt-get install --yes --no-install-recommends \
    curl \
    && echo TODO

# core GDAL build requirements
RUN apt-get install --yes --no-install-recommends \
    bison \
    cmake \
    g++ \
    libproj-dev \
    make \
    && echo TODO

# GDAL external driver dependencies
#  * OPENCAD internal library enabled
RUN apt-get install --yes --no-install-recommends \
    libexpat-dev \
    libfreexl-dev \
    libgeos-dev \
    libgeotiff-dev \
    libgif-dev \
    libhdf5-dev \
    libheif-dev \
    libjpeg-dev \
    libjson-c-dev \
    libjxl-dev \
    libkml-dev \
    libpng-dev \
    libpoppler-private-dev \
    libpq-dev \
    libqhull-dev \
    librasterlite2-dev \
    libspatialite-dev \
    libxerces-c-dev \
    && echo TODO

# # gdal builds without this, but test suite fails without, why?
RUN apt-get install --yes --no-install-recommends \
    libcrypto++-dev \
    libgtest-dev
#     # libcrypto++8

# for GDAL test suite and Python bindings
RUN apt-get install --yes --no-install-recommends \
    swig

ARG PIP_NO_CACHE_DIR=1
# and disable the warning about running as root without a venv
ARG PIP_ROOT_USER_ACTION=ignore

# DGAL wants NumPy *before compiling
ARG NPVER
RUN pip install --upgrade pip setuptools wheel \
    && pip install numpy==$NPVER

# # install TileDB (BEWARE! this assumes x86_64 arch)
# ARG TDBVER
# ARG TDBREF
# RUN cd /usr/local && curl --location \
#    https://github.com/TileDB-Inc/TileDB/releases/download/$TDBVER/tiledb-linux-x86_64-$TDBVER-$TDBREF.tar.gz \
#    |tar -xz
# RUN ls -doh /usr/local/include/* /usr/local/lib/*

# # ESRI File Geodatabase (FileGDB)
# RUN cd /opt && curl --location \
#     http://appsforms.esri.com/storage/apps/downloads/software/filegdb_api_1_4-64.tar.gz \
#     |tar -xz && \
#     mv FileGDB_API-64/include/*.h /usr/local/include/ && \
#     mv FileGDB_API-64/lib/*.so /usr/local/lib/
# not sure why above doesn't work; see alterative here: https://github.com/todorus/openkaart-data/blob/develop/geodatabase_conversion/Dockerfile#L22

# fetch/prep GDAL source
ARG GDVER
ARG GDPATH=https://github.com/OSGeo/gdal/releases/download/v$GDVER/gdal
RUN curl --location ${GDPATH}-$GDVER.tar.gz \
      |tar -xz && \
    curl --location ${GDPATH}autotest-$GDVER.tar.gz \
      |tar -xz && \
    mv gdalautotest-$GDVER gdal-$GDVER/autotest
RUN mkdir gdal-$GDVER/build
WORKDIR /gdal-$GDVER/build

# configure GDAL
ARG PYVER
RUN cmake .. -DCMAKE_BUILD_TYPE=Release \
      -DPython_ROOT=/usr/local/lib/python$PYVER \
      |tee /gdal-cmake.txt
    #   -DGDAL_USE_INTERNAL_LIBS=OFF \
    #   -DGDAL_BUILD_OPTIONAL_DRIVERS=OFF \
    #   -DOGR_BUILD_OPTIONAL_DRIVERS=OFF \
    #   -DGDAL_ENABLE_DRIVER_JPEG=ON \
    #   -DGDAL_ENABLE_DRIVER_RAW=ON \
    #   -DBUILD_TESTING=ON \
    #   ...

# build GDAL
RUN cmake --build . --parallel $(nproc)

# # run tests
# RUN pip install --requirement ../autotest/requirements.txt
# RUN ctest -v --output-on-failure --parallel $(nproc) ||:
# # TODO: let's put the pip modules into a venv so we don't have to hard-code deps
# #  - BEWARE: ctest is hard-coded to usr /usr/local/bin/python3 and doesn't honor venv
# # RUN python -m venv .venv && . .venv/bin/activate \
# #     && pip install --upgrade pip setuptools wheel \
# #     && pip install --requirement ../autotest/requirements.txt
# # RUN . .venv/bin/activate && \
# #     export PYTHONPATH=./.venv/lib/python3.12/site-packages && \
# #     ctest -v --output-on-failure --parallel $(nproc)
# # RUN pip uninstall --yes pytest pytest-sugar pytest-env pytest-benchmark lxml jsonschema filelock \
# #     attrs filelock iniconfig jsonschema-specifications packaging  pluggy py-cpuinfo referencing rpds-py termcolor \
# #     && pip list
# # we should be left with only setuptools, wheel, & numpy

# install GDAL
RUN cmake --install . --prefix /usr/local/gdal

#======================================================================
ARG PYVER
ARG DEBVER
FROM python:$PYVER-slim-$DEBVER

LABEL org.opencontainers.image.source=$HERE

COPY --from=build-ffmpeg /usr/local/bin/ff* /usr/local/bin/
COPY --from=build-ffmpeg /ffinfo.txt /

COPY --from=build-gdal /usr/local/gdal/bin /usr/local/bin
COPY --from=build-gdal /usr/local/gdal/lib /usr/local/lib
COPY --from=build-gdal /usr/local/gdal/include /usr/local/include
COPY --from=build-gdal /usr/local/gdal/share /usr/local/share
COPY --from=build-gdal /gdal-cmake.txt /
# COPY --from=build-gdal /usr/local/lib/libtiledb* /usr/local/lib/
# COPY --from=build-gdal /usr/local/lib/libFileGDBAPI.so /usr/local/lib/
# COPY --from=build-gdal /usr/local/lib/libfgdbunixrtl.so /usr/local/lib/

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get upgrade --yes

# neede to build fiona against GDAL
RUN apt-get install --yes --no-install-recommends \
    g++

# runtime dependencies
# TODO: create this list dynamically in build-gdal above
RUN apt-get install --yes --no-install-recommends \
    libcrypto++8 \
    libcurl3-gnutls \
    libdeflate0 \
    libfreexl1 \
    libgeos-c1v5 \
    libgeotiff5 \
    libgif7 \
    libhdf5-103 \
    libheif1 \
    libimath-3-1-29 \
    libjson-c5 \
    libjxl0.7 \
    libkmlbase1 \
    libkmldom1 \
    libkmlengine1 \
    libmariadb3 \
    libopenexr-3-1-30 \
    libpng16-16 \
    libpoppler126 \
    libpq5 \
    libproj25 \
    libqhull-r8.0 \
    librasterlite2-1 \
    libspatialite7 \
    libtiff6 \
    libxerces-c3.2 \
    && rm -rf /var/lib/apt/lists/*
    # libpcre3 \

ARG PIP_NO_CACHE_DIR=1
# and disable the warning about running as root without a venv
ARG PIP_ROOT_USER_ACTION=ignore

RUN pip install --upgrade pip setuptools

# build/install fiona against new GDAL
ARG FIONAVER
RUN pip install --no-binary fiona fiona==$FIONAVER

# and our other favorite GIS modules
COPY require.pip .
RUN pip install --requirement require.pip \
    && rm require.pip

# now remove fiona build deps
RUN apt-get --yes purge \
   g++ \
   && apt-get --yes autoremove

# make sure we didn't remove anything still needed
RUN lddout=$(bash -c '2>&1 ldd /usr/local/bin/{gdal,ogr}*'); \
    if echo "$lddout" |grep -q 'not found'; then \
       echo "$lddout" |grep 'not found' |sort |uniq -c; \
       exit 1; \
    fi

# show what we got
RUN cat /ffinfo.txt
RUN cat /gdal-cmake.txt
RUN gdal-config --formats |tr ' ' '\n' |sort --ignore-case |tee /gdal-formats.txt
RUN pip list --verbose |tee /pip-list.txt

# see docker output line-by-line
ENV PYTHONUNBUFFERED=yessir

# in ephemeral containers creating .pyc files after build is a waste of time
ENV PYTHONDONTWRITEBYTECODE=aye

# TODO: install PostGIS now with a bunch of cool FDWs!
