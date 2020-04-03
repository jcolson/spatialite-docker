ARG BASE=alpine:3.11
FROM $BASE as build

RUN echo "@edge http://dl-cdn.alpinelinux.org/alpine/edge/main" >> /etc/apk/repositories
RUN echo "@edge-testing http://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories
RUN echo "@edge-community http://dl-5.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories

RUN apk update && \
  apk --no-cache --update upgrade musl && \
  apk --no-cache add --upgrade --force-overwrite apk-tools@edge && \
  apk --no-cache add --update --force-overwrite wget gcc g++ make automake \
  libtool autoconf curl fossil git libc-dev sqlite sqlite-dev \
  zlib-dev libxml2-dev go "poppler@edge" linux-headers expat-dev \
#  "gdal-dev@edge-community" "gdal@edge-community" \
  "json-c@edge" "mariadb-connector-c@edge" "icu-libs@edge" \
  readline-dev ncurses-dev readline ncurses-static libc6-compat && \
  rm -rf /var/cache/apk/*

COPY . /src

ENV USER me

RUN wget https://github.com/OSGeo/PROJ/archive/6.2.1.tar.gz && tar xvfz 6.2.1.tar.gz && rm 6.2.1.tar.gz && cd PROJ-6.2.1 && ./autogen.sh && ./configure && make install

RUN wget https://github.com/OSGeo/gdal/archive/v3.0.4.tar.gz && tar xvfz v3.0.4.tar.gz && rm v3.0.4.tar.gz && cd gdal-3.0.4/gdal && ./autogen.sh && ./configure && make install

# tried 3.8.1
# 'libgeos_c' (>= v.3.7.0) is required
RUN wget https://github.com/libgeos/geos/archive/3.7.3.tar.gz && tar xvfz 3.7.3.tar.gz && rm 3.7.3.tar.gz && cd geos-3.7.3 && ./autogen.sh && ./configure && make install

RUN fossil clone https://www.gaia-gis.it/fossil/freexl freexl.fossil && mkdir freexl && cd freexl && fossil open ../freexl.fossil && ./configure && make -j8 && make install

RUN git clone "https://git.osgeo.org/gitea/rttopo/librttopo.git" && cd librttopo && ./autogen.sh && ./configure && make -j8 && make install

ENV CPPFLAGS "-DACCEPT_USE_OF_DEPRECATED_PROJ_API_H"
RUN fossil clone https://www.gaia-gis.it/fossil/libspatialite libspatialite.fossil && mkdir libspatialite && cd libspatialite && fossil open ../libspatialite.fossil \
&& patch -i /src/libspatialite.patch && aclocal && autoconf \
&& ./configure --disable-dependency-tracking --enable-rttopo=yes --enable-proj=yes --enable-geos=yes --enable-gcp=yes --enable-libxml2=yes && make -j8 && make install

RUN fossil clone https://www.gaia-gis.it/fossil/readosm readosm.fossil && mkdir readosm && cd readosm && fossil open ../readosm.fossil && ./configure && make -j8 && make install

RUN fossil clone https://www.gaia-gis.it/fossil/spatialite-tools spatialite-tools.fossil && mkdir spatialite-tools && cd spatialite-tools && fossil open ../spatialite-tools.fossil && ./configure && make -j8 && make install

RUN cp /usr/local/bin/* /usr/bin/
RUN cp -R /usr/local/lib/* /usr/lib/

# Create a minimal instance
FROM $BASE

# copy libs (maintaining symlinks)
COPY --from=build /usr/lib/ /usr/lib
COPY --from=build /usr/bin/ /usr/bin
#COPY --from=build /usr/share/proj/proj.db /usr/share/proj/proj.db

# remove broken symlinks
RUN find -L /usr/lib -maxdepth 1 -type l -delete

# remove directories
RUN find /usr/lib -mindepth 1 -maxdepth 1 -type d -exec rm -r {} \;

# copy binaries
COPY --from=build /usr/bin/spatialite* /usr/bin/

