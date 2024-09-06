ARG HERE=https://github.com/dotysan/python-gis

ARG PYVER=3.11

ARG GDVER=3.9.2
ARG GDREPO=OSGeo/gdal

ARG PROJVER=9.4.1
ARG PROJREPO=OSGeo/PROJ

ARG PDREV=6684

ARG NPVER=2.1.*
ARG FIONAVER=1.9.*

# ARG TDBVER=2.19.1
# ARG TDBREF=29ceb3e7

ARG DEBVER=bookworm

# END ARGs ------------------------------------------------------------

#======================================================================
FROM python:$PYVER-slim-$DEBVER AS build-gdal

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install --yes --no-install-recommends \
        ca-certificates \
        cmake \
        curl \
        g++ \
        git \
        libcurl4-openssl-dev \
        libdeflate-dev \
        libfreexl-dev \
        libgeos-dev \
        libgif-dev \
        libglib2.0-dev \
        libheif-dev \
        libjpeg-dev \
        libjson-c-dev \
        libjxl-dev \
        liblcms2-dev \
        liblerc-dev \
        liblzma-dev \
        libmariadb-dev-compat \
        libopenexr-dev \
        libopenjp2-7-dev \
        libpng-dev \
        libpq-dev \
        libqhull-dev \
        libsqlite3-dev \
        libwebp-dev \
        libxerces-c-dev \
        libxml2-dev \
        libzstd-dev \
        make \
        ocl-icd-opencl-dev \
        sqlite3 \
        swig \
    && apt-get upgrade --yes
#         libopenexr-dev \


#----------------------------------------------------------------------

ARG PIP_NO_CACHE_DIR=1
# and disable the warning about running as root without a venv
ARG PIP_ROOT_USER_ACTION=ignore
RUN pip install --upgrade pip setuptools wheel

# DGAL wants NumPy *before compiling
ARG NPVER
RUN pip install numpy==$NPVER

#----------------------------------------------------------------------

# # Let's build PROJ from source with much newer version
ARG PROJVER
ARG PROJREPO
ARG PROJDL="https://github.com/$PROJREPO/releases/download"
ARG PROJARCH="$PROJDL/$PROJVER/proj-$PROJVER.tar.gz"
RUN curl --location "$PROJARCH" |tar xz

RUN mkdir /proj-$PROJVER/build
WORKDIR /proj-$PROJVER/build
ARG CLICOLOR_FORCE=1
RUN cmake .. -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_COLOR_DIAGNOSTICS=ON \
        -DCMAKE_INSTALL_PREFIX=/usr/local/proj \
        -DBUILD_SHARED_LIBS=ON \
        -DBUILD_TESTING=OFF \
        -DBUILD_APPS=ON \
        -DENABLE_CURL=ON \
        -DENABLE_TIFF=OFF \
    2>&1 |tee /proj-cmake.txt

RUN cmake --build . --parallel $(nproc)
RUN cmake --install .

#----------------------------------------------------------------------

# # install TileDB (BEWARE! this assumes x86_64 arch)
# ARG TDBVER
# ARG TDBREF
# RUN cd /usr/local && curl --location \
#    https://github.com/TileDB-Inc/TileDB/releases/download/$TDBVER/tiledb-linux-x86_64-$TDBVER-$TDBREF.tar.gz \
#    |tar -xz
# RUN ls -doh /usr/local/include/* /usr/local/lib/*

#----------------------------------------------------------------------

# Build against PDFium instead of using slow system Poppler
WORKDIR /gclient
RUN git clone --depth 1 --branch=main --single-branch \
        https://chromium.googlesource.com/chromium/tools/depot_tools.git
ARG PATH="/gclient/depot_tools:$PATH"

ARG DEPOT_TOOLS_UPDATE=0
RUN gclient config --verbose --verbose --unmanaged \
        --custom-var=checkout_configuration=minimal \
        https://pdfium.googlesource.com/pdfium.git
ARG PDREV
RUN gclient sync --verbose --shallow --no-history --revision="chromium/$PDREV"

WORKDIR /gclient/pdfium

COPY code.patch .
RUN git apply --verbose code.patch

# when is_clang=false and is_debug=false we get a free-nonheap warning; ignore it
COPY noerror-freenonheap.patch .
RUN git apply --verbose noerror-freenonheap.patch

COPY args_release_linux.gn out/Release/args.gn
RUN gn gen out/Release --color --verbose

RUN ninja -C out/Release pdfium
WORKDIR /

#----------------------------------------------------------------------

# ARG DEBIAN_FRONTEND
RUN apt-get --yes install --no-install-recommends \
        libkml-dev
# can't install libkml-dev before pdfium is built, since it drags in libstdc++-12-dev and poisons our libstdc++-11-dev build

#----------------------------------------------------------------------

# fetch/prep GDAL source
ARG GDVER
ARG GDREPO
ARG GHDL="https://github.com/$GDREPO/releases/download"
ARG GDARCH="$GHDL/v$GDVER/gdal-$GDVER.tar.gz"
RUN curl --location "$GDARCH" |tar xz

WORKDIR /gdal-$GDVER
COPY 2024-0*.patch ./
RUN git apply --verbose 2024-05-22T17:23.fe08ea1b31.PDF-split-import-of-SDK-headers.patch
RUN git apply --verbose 2024-08-25T12:37.PDF-update-to-PDFium-6677.patch

WORKDIR /gdal-$GDVER/build
# configure GDAL
ARG PYVER
ARG CLICOLOR_FORCE=1
RUN cmake .. -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_COLOR_DIAGNOSTICS=ON \
      -DPython_ROOT=/usr/local/lib/python$PYVER \
      -DGDAL_BUILD_OPTIONAL_DRIVERS=OFF \
      -DOGR_BUILD_OPTIONAL_DRIVERS=OFF \
      -DBUILD_TESTING=OFF \
      \
      -DGDAL_ENABLE_DRIVER_BMP=ON \
      \
      -DGDAL_ENABLE_DRIVER_GIF=ON \
      -DGDAL_USE_GIF=ON \
      -DGDAL_USE_GIF_INTERNAL=OFF \
      \
      -DGDAL_ENABLE_DRIVER_PNG=ON \
      -DGDAL_USE_PNG_INTERNAL=OFF \
      \
      -DGDAL_ENABLE_DRIVER_JPEG=ON \
      -DGDAL_ENABLE_DRIVER_JP2OPENJPEG=ON \
      -DGDAL_USE_JPEG_INTERNAL=OFF \
      -DGDAL_USE_OPENJPEG=ON \
      \
      -DGDAL_ENABLE_DRIVER_HEIF=ON \
      \
      -DGDAL_USE_TIFF_INTERNAL=ON \
      -DGDAL_USE_GEOTIFF_INTERNAL=ON \
      -DGDAL_ENABLE_DRIVER_GTIFF=ON \
      -DGDAL_ENABLE_DRIVER_CALS=ON \
      \
      -DGDAL_USE_DEFLATE=ON \
      -DGDAL_USE_ZLIB=ON \
      -DGDAL_USE_LIBLZMA=ON \
      -DGDAL_USE_ZSTD=ON \
      -DGDAL_USE_LERC=ON \
      -DGDAL_USE_WEBP=ON \
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
      \
      -DGDAL_USE_CURL=ON \
      -DOGR_ENABLE_DRIVER_WFS=ON \
      -DGDAL_ENABLE_DRIVER_EEDA=ON \
      -DGDAL_ENABLE_DRIVER_OGCAPI=ON \
      -DOGR_ENABLE_DRIVER_OGCAPI=ON \
      \
      -DGDAL_FIND_PACKAGE_PROJ_MODE=MODULE \
      -DPROJ_INCLUDE_DIR=/usr/local/proj/include \
      -DPROJ_LIBRARY=/usr/local/proj/lib/libproj.so \
      \
      -DGDAL_ENABLE_DRIVER_PDF=ON \
      -DGDAL_USE_POPPLER=OFF \
      -DGDAL_USE_PDFIUM=ON \
      -DPDFIUM_INCLUDE_DIR=/gclient/pdfium \
      -DPDFIUM_LIBRARY=/gclient/pdfium/out/Release/obj/libpdfium.a \
      \
      -DOGR_ENABLE_DRIVER_MYSQL=ON \
      -DOGR_ENABLE_DRIVER_PG=ON \
      -DOGR_ENABLE_DRIVER_PGDUMP=ON \
      -DGDAL_ENABLE_DRIVER_POSTGISRASTER=ON \
      -DGDAL_USE_SQLITE3=ON \
      -DOGR_ENABLE_DRIVER_SQLITE=ON \
      -DGDAL_ENABLE_DRIVER_RASTERLITE=ON \
      \
      -DGDAL_ENABLE_DRIVER_USGSDEM=ON \
      -DGDAL_ENABLE_DRIVER_DTED=ON \
      -DGDAL_ENABLE_DRIVER_SDTS=ON \
      -DOGR_ENABLE_DRIVER_SDTS=ON \
      -DGDAL_ENABLE_DRIVER_ESRIC=ON \
      -DGDAL_ENABLE_DRIVER_PDS=ON \
      \
      -DOGR_ENABLE_DRIVER_CAD=ON \
      -DGDAL_USE_OPENCAD_INTERNAL=ON \
      \
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
#       -DGDAL_USE_INTERNAL_LIBS=OFF \
    # compile from source with --enable-threadsafe and then -DGDAL_ENABLE_DRIVER_HDF5=ON \

RUN cp --recursive /gclient/pdfium/third_party/abseil-cpp/absl /gclient/pdfium/

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

# needed to build fiona against GDAL
RUN apt-get install --yes --no-install-recommends \
    g++
# -11 or -12?

# runtime dependencies
# TODO: create this list dynamically in build-gdal above
RUN apt-get install --yes --no-install-recommends \
        libcurl4 \
        libdeflate0 \
        libfreexl1 \
        libgeos-c1v5 \
        libgif7 \
        libheif1 \
        libjpeg62-turbo \
        libjson-c5 \
        libjxl0.7 \
        libkmlbase1 \
        libkmldom1 \
        libkmlengine1 \
        liblcms2-2 \
        liblerc4 \
        libmariadb3 \
        libopenjp2-7 \
        libpng16-16 \
        libpq5 \
        libqhull-r8.0 \
        libwebp7 \
        libxerces-c3.2 \
        libxml2 \
        ocl-icd-libopencl1
        # libpcre3 \

COPY --from=build-gdal /usr/local/proj/lib/libproj* /usr/local/lib/
COPY --from=build-gdal /usr/local/proj/share /usr/local/share

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
RUN apt-get purge --yes \
   g++ \
   && apt-get autopurge --yes

# and finaly handy stuff to have in a devcontainer TODO: create separate -devcon image
RUN apt-get install --yes --no-install-recommends \
        file \
        gawk \
        git-lfs \
        mc \
        psmisc \
        sudo \
    && rm -rf /var/lib/apt/lists/*

# make sure we didn't remove anything still needed
RUN lddout=$(bash -c '2>&1 ldd /usr/local/bin/{gdal,ogr}*'); \
    if echo "$lddout" |grep -q 'not found'; then \
       echo "$lddout" |grep 'not found' |sort |uniq -c; \
       exit 1; \
    fi |tee /gdal-ldd-sanity.txt

# show what we got
RUN cat /gdal-cmake.txt
RUN gdal-config --formats |tr ' ' '\n' |sort --ignore-case |tee /gdal-formats.txt
RUN (gdalinfo --formats && ogrinfo --formats) \
      |sort -u |grep -v ^Supported |tee /all-formats.txt
RUN pip list --verbose |tee /pip-list.txt

# see docker output line-by-line
ENV PYTHONUNBUFFERED=yessir

# in ephemeral containers creating .pyc files after build is a waste of time
ENV PYTHONDONTWRITEBYTECODE=aye

# for devcontainer
RUN useradd --create-home --shell=/bin/bash gisuser
# should be UID:GID == 1000:1000
RUN echo 'gisuser ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/gisuser
USER gisuser

# TODO: install PostGIS now with a bunch of cool FDWs!
