# TODO: add dockerfile version here; require BuildKit
ARG HERE=https://github.com/dotysan/python-gis

ARG PYVER=3.11
ARG GDVER=3.9.1
ARG PROJVER=9.4.1
ARG PDFREV=6309
ARG NPVER=2.0.*
ARG FIONAVER=1.9.*

# ARG TDBVER=2.19.1
# ARG TDBREF=29ceb3e7

ARG DEBVER=bookworm
ARG FFREF=a78f2b8677bed1b8130deb46af137ada1d0070d5
#======================================================================
FROM debian:$DEBVER-slim AS build-ffmpeg

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install --yes --no-install-recommends \
        bzip2 \
        ca-certificates \
        g++ \
        git \
        make \
        patch \
        pkgconf \
        wget \
    && apt-get autopurge --yes \
    && apt-get upgrade --yes

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
# END build-ffmpeg-----------------------------------------------------

ARG PYVER
ARG DEBVER
#======================================================================
FROM python:$PYVER-slim-$DEBVER AS build-gdal

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get --yes install --no-install-recommends \
        bison \
        cmake \
        curl \
        g++ \
        make \
        libbrotli-dev \
        libcurl4-openssl-dev \
        libexpat-dev \
        libfreexl-dev \
        libgeos-dev \
        libgif-dev \
        libheif-dev \
        libjpeg-dev \
        libjson-c-dev \
        libkml-dev \
        liblcms2-dev \
        libmariadb-dev-compat \
        libopenexr-dev \
        libopenjp2-7-dev \
        libpcre2-dev \
        libpng-dev \
        libpq-dev \
        libqhull-dev \
        libsqlite3-dev \
        libtiff-dev \
        libxerces-c-dev \
        libxml2-dev \
        ocl-icd-opencl-dev \
        sqlite3 \
        swig \
    && apt-get --yes autopurge \
    && apt-get --yes upgrade

ARG PIP_NO_CACHE_DIR=1
# and disable the warning about running as root without a venv
ARG PIP_ROOT_USER_ACTION=ignore

# DGAL wants NumPy *before compiling
ARG NPVER
RUN pip install --upgrade pip setuptools wheel \
    && pip install numpy==$NPVER

# Let's build PROJ from source with much newer version
ARG PROJVER
ARG PROJ_TARBALL=https://github.com/OSGeo/PROJ/releases/download/${PROJVER}/proj-${PROJVER}.tar.gz
RUN curl --location ${PROJ_TARBALL} |tar xz
RUN mkdir /proj-${PROJVER}/build
WORKDIR /proj-${PROJVER}/build

RUN cmake .. -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr/local/proj \
    -DBUILD_SHARED_LIBS=ON \
    -DBUILD_TESTING=OFF \
    -DBUILD_APPS=OFF \
    \
    |tee /proj-cmake.txt

RUN cmake --build . --parallel $(nproc)
RUN cmake --install .
WORKDIR /

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

# Build against PDFium instead of using slow system Poppler
ARG PDFREV
# TODO: take PDFREPO '3_9' from GDVER=3.9.1
ARG PDFREPO=rouault/pdfium_build_gdal_3_9
ARG PDFTAG=pdfium_${PDFREV}_v1
ARG PDFINSTALL=https://github.com/${PDFREPO}/releases/download/${PDFTAG}/install-ubuntu2004-rev${PDFREV}.tar.gz
RUN curl --location ${PDFINSTALL} |tar xz
# this creates /install/{include,lib}/

#----------------------------------------------------------------------
# JPEG XL (note it requires libtiff; how does this conflict with GDAL internal libtiff?)
ARG JXL_TARBALL=https://github.com/libjxl/libjxl/archive/refs/tags/v0.10.3.tar.gz
RUN curl --location ${JXL_TARBALL} |tar xz

# RUN mkdir /libjxl-0.10.3/third_party/{highway,brotli}
RUN curl --location https://github.com/google/highway/releases/download/1.2.0/highway-1.2.0.tar.gz \
    |tar xvz -C /libjxl-0.10.3/third_party/highway --strip-components=1
# the e5ab130 commit is from Jun 8, 2023 and
# the newest is 4578abf dated Jun 26, 2024
# RUN curl --location https://github.com/webmproject/sjpeg/tarball/e5ab13008bb214deb66d5f3e17ca2f8dbff150bf \
RUN curl --location https://github.com/webmproject/sjpeg/tarball/4578abf18ed8b81290c6fe5c23eb7a58c8f38212 \
    |tar xvz -C /libjxl-0.10.3/third_party/sjpeg --strip-components=1
RUN curl --location https://skia.googlesource.com/skcms/+archive/42030a771244ba67f86b1c1c76a6493f873c5f91.tar.gz \
    |tar xvz -C /libjxl-0.10.3/third_party/skcms --strip-components=0
# RUN bash -x /libjxl-0.10.3/deps.sh

RUN mkdir /libjxl-0.10.3/build
WORKDIR /libjxl-0.10.3/build
RUN cmake ..  -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_TESTING=OFF
    # -DBUILD_SHARED_LIBS=ON \
    # -DCMAKE_INSTALL_PREFIX=/usr/local/libjxl \
RUN cmake --build . --parallel $(nproc)
RUN cmake --install .
WORKDIR /
#----------------------------------------------------------------------

# fetch/prep GDAL source
ARG GDVER
ARG GDPATH=https://github.com/OSGeo/gdal/releases/download/v$GDVER/gdal
RUN curl --location ${GDPATH}-$GDVER.tar.gz |tar xz
RUN mkdir gdal-$GDVER/build
WORKDIR /gdal-$GDVER/build
# configure GDAL
ARG PYVER
RUN cmake .. -DCMAKE_BUILD_TYPE=Release \
      -DPython_ROOT=/usr/local/lib/python$PYVER \
      -DGDAL_USE_INTERNAL_LIBS=OFF \
      -DGDAL_BUILD_OPTIONAL_DRIVERS=OFF \
      -DOGR_BUILD_OPTIONAL_DRIVERS=OFF \
      -DBUILD_TESTING=OFF \
      \
      -DGDAL_FIND_PACKAGE_PROJ_MODE=MODULE \
      -DPROJ_INCLUDE_DIR=/usr/local/proj/include \
      -DPROJ_LIBRARY=/usr/local/proj/lib/libproj.so \
      \
      -DGDAL_ENABLE_DRIVER_BMP=ON \
      -DGDAL_ENABLE_DRIVER_GIF=ON \
      -DGDAL_USE_GIF=ON \
      -DGDAL_USE_GIF_INTERNAL=OFF \
      -DGDAL_ENABLE_DRIVER_PNG=ON \
      -DGDAL_USE_PNG_INTERNAL=OFF \
      -DGDAL_ENABLE_DRIVER_JPEG=ON \
      -DGDAL_ENABLE_DRIVER_JP2OPENJPEG=ON \
      -DGDAL_USE_JPEG_INTERNAL=OFF \
      -DGDAL_USE_OPENJPEG=ON \
      -DGDAL_ENABLE_DRIVER_HEIF=ON \
      -DGDAL_USE_TIFF_INTERNAL=ON \
      -DGDAL_USE_GEOTIFF_INTERNAL=ON \
      \
      -DGDAL_ENABLE_DRIVER_JPEGXL=ON \
      -DGDAL_USE_JXL=ON \
      \
      -DGDAL_ENABLE_DRIVER_KMLSUPEROVERLAY=ON \
      -DOGR_ENABLE_DRIVER_LIBKML=ON \
      \
      -DGDAL_ENABLE_DRIVER_HTTP=ON \
      -DGDAL_ENABLE_DRIVER_RAW=ON \
      -DGDAL_ENABLE_DRIVER_WCS=ON \
      -DGDAL_ENABLE_DRIVER_WMS=ON \
      -DGDAL_ENABLE_DRIVER_WMTS=ON \
      -DGDAL_USE_CURL=ON \
      -DOGR_ENABLE_DRIVER_WFS=ON \
      -DGDAL_ENABLE_DRIVER_EEDA=ON \
      -DGDAL_ENABLE_DRIVER_OGCAPI=ON \
      -DOGR_ENABLE_DRIVER_OGCAPI=ON \
      \
      -DGDAL_ENABLE_DRIVER_PDF=ON \
      -DGDAL_USE_POPPLER=OFF \
      -DGDAL_USE_PDFIUM=ON \
      -DPDFIUM_INCLUDE_DIR=/install/include/pdfium \
      -DPDFIUM_LIBRARY=/install/lib/libpdfium.a \
      \
      -DOGR_ENABLE_DRIVER_MYSQL=ON \
      -DOGR_ENABLE_DRIVER_PG=ON \
      -DOGR_ENABLE_DRIVER_PGDUMP=ON \
      -DGDAL_ENABLE_DRIVER_POSTGISRASTER=ON \
      -DOGR_ENABLE_DRIVER_SQLITE=ON \
      -DGDAL_ENABLE_DRIVER_RASTERLITE=ON \
      \
      -DGDAL_ENABLE_DRIVER_ESRIC=ON \
      -DOGR_ENABLE_DRIVER_CAD=ON \
      -DGDAL_USE_OPENCAD_INTERNAL=ON \
      -DOGR_ENABLE_DRIVER_CSV=ON \
      -DOGR_ENABLE_DRIVER_CSW=ON \
      -DOGR_ENABLE_DRIVER_DXF=ON \
      -DOGR_ENABLE_DRIVER_ELASTIC=ON \
      -DOGR_ENABLE_DRIVER_GML=ON \
      -DOGR_ENABLE_DRIVER_GMLAS=ON \
      -DOGR_ENABLE_DRIVER_GPKG=ON \
      -DOGR_ENABLE_DRIVER_GPX=ON \
      -DOGR_ENABLE_DRIVER_JSONFG=ON \
      -DOGR_ENABLE_DRIVER_MAPML=ON \
      -DOGR_ENABLE_DRIVER_MVT=ON \
      -DOGR_ENABLE_DRIVER_OPENFILEGDB=ON \
      -DOGR_ENABLE_DRIVER_OSM=ON \
      -DOGR_ENABLE_DRIVER_SVG=ON \
      -DOGR_ENABLE_DRIVER_TIGER=ON \
      -DOGR_ENABLE_DRIVER_XLS=ON \
      -DOGR_ENABLE_DRIVER_XLSX=ON \
      \
      2>&1 |tee /gdal-cmake.txt
    # compile from source with --enable-threadsafe and then -DGDAL_ENABLE_DRIVER_HDF5=ON \

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
# END build-gdal-------------------------------------------------------

#======================================================================
ARG PYVER
ARG DEBVER
FROM python:$PYVER-slim-$DEBVER

ARG HERE
LABEL org.opencontainers.image.source=$HERE

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get upgrade --yes

# neede to build fiona against GDAL
RUN apt-get install --yes --no-install-recommends \
    g++

# runtime dependencies
# TODO: create this list dynamically in build-gdal above
RUN apt-get install --yes --no-install-recommends \
    libbrotli1 \
    libcrypto++8 \
    libcurl4 \
    libdeflate0 \
    libfreexl1 \
    libgeos-c1v5 \
    libgif7 \
    libheif1 \
    libimath-3-1-29 \
    libjson-c5 \
    libkmlbase1 \
    libkmldom1 \
    libkmlengine1 \
    liblcms2-2 \
    libmariadb3 \
    libopenexr-3-1-30 \
    libopenjp2-7 \
    libpng16-16 \
    libpq5 \
    libqhull-r8.0 \
    libtiff6 \
    libxerces-c3.2 \
    libxml2 \
    ocl-icd-libopencl1 \
    && rm -rf /var/lib/apt/lists/*
    # libpcre3 \

COPY --from=build-ffmpeg /usr/local/bin/ff* /usr/local/bin/
COPY --from=build-ffmpeg /ffinfo.txt /

COPY --from=build-gdal /usr/local/proj/lib /usr/local/lib
COPY --from=build-gdal /usr/local/proj/share /usr/local/share

COPY --from=build-gdal /usr/local/lib/libjxl* /usr/local/lib

COPY --from=build-gdal /usr/local/gdal/bin /usr/local/bin
COPY --from=build-gdal /usr/local/gdal/lib /usr/local/lib

COPY --from=build-gdal /usr/local/gdal/include /usr/local/include
# gdal headers are needed to install fiona below

COPY --from=build-gdal /usr/local/gdal/share /usr/local/share

COPY --from=build-gdal /*.txt /

# COPY --from=build-gdal /usr/local/lib/libtiledb* /usr/local/lib/
# COPY --from=build-gdal /usr/local/lib/libFileGDBAPI.so /usr/local/lib/
# COPY --from=build-gdal /usr/local/lib/libfgdbunixrtl.so /usr/local/lib/

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
   && apt-get --yes autopurge

# make sure we didn't remove anything still needed
RUN lddout=$(bash -c '2>&1 ldd /usr/local/bin/{gdal,ogr}*'); \
    if echo "$lddout" |grep -q 'not found'; then \
       echo "$lddout" |grep 'not found' |sort |uniq -c; \
       exit 1; \
    fi |tee /gdal-ldd-sanity.txt

# show what we got
RUN cat /ffinfo.txt
RUN cat /gdal-cmake.txt
RUN gdal-config --formats |tr ' ' '\n' |sort --ignore-case |tee /gdal-formats.txt
RUN (gdalinfo --formats && ogrinfo --formats) \
      |sort -u |grep -v ^Supported |tee /all-formats.txt
RUN pip list --verbose |tee /pip-list.txt

# see docker output line-by-line
ENV PYTHONUNBUFFERED=yessir

# in ephemeral containers creating .pyc files after build is a waste of time
ENV PYTHONDONTWRITEBYTECODE=aye

# TODO: install PostGIS now with a bunch of cool FDWs!
