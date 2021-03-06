FROM alpine:3.9

LABEL maintainer="jbbodart"

ENV UID=991
ENV GID=991
ENV RTORRENT_LISTEN_PORT=49314
ENV RTORRENT_DHT_PORT=49313
ENV DNS_SERVER_IP='9.9.9.9'

ARG MEDIAINFO_VER="18.12"

# Add flood configuration before build
COPY config/flood_config.js /tmp/config.js

RUN NB_CORES=${BUILD_CORES-$(getconf _NPROCESSORS_CONF)} \
  && addgroup -g ${GID} rtorrent \
  && adduser -h /home/rtorrent -s /bin/sh -G rtorrent -D -u ${UID} rtorrent \
  && build_pkgs="build-base git libtool automake autoconf tar xz binutils curl-dev cppunit-dev libressl-dev zlib-dev linux-headers ncurses-dev libxml2-dev" \
  && runtime_pkgs="supervisor shadow su-exec nginx ca-certificates php7 php7-fpm php7-json openvpn curl python2 nodejs nodejs-npm ffmpeg sox unzip unrar" \
  && apk -U upgrade \
  && apk add --no-cache --virtual=build-dependencies ${build_pkgs} \
  && apk add --no-cache ${runtime_pkgs} \

# compile mktorrent
  && cd /tmp \
  && git clone https://github.com/pobrn/mktorrent.git \
  && cd /tmp/mktorrent \
  && make -j ${NB_CORES} \
  && make install \

# compile xmlrpc-c
  && cd /tmp \
  && curl -O https://iweb.dl.sourceforge.net/project/xmlrpc-c/Xmlrpc-c%20Super%20Stable/1.39.13/xmlrpc-c-1.39.13.tgz \
  && tar zxvf xmlrpc-c-1.39.13.tgz \
  && cd xmlrpc-c-1.39.13 \
  && ./configure --enable-libxml2-backend --disable-cgi-server --disable-libwww-client --disable-wininet-client --disable-abyss-server \
  && make -j ${NB_CORES} \
  && make install \
  && make -C tools -j ${NB_CORES} \
  && make -C tools install \

# compile libtorrent
  && cd /tmp \
  && git clone https://github.com/rakshasa/libtorrent.git \
  && cd /tmp/libtorrent \
  && ./autogen.sh \
  && ./configure \
  && make -j ${NB_CORES} \
  && make install \

# compile rtorrent
  && cd /tmp \
  && git clone https://github.com/rakshasa/rtorrent.git \
  && cd /tmp/rtorrent \
  && ./autogen.sh \
  && ./configure --with-xmlrpc-c \
  && make -j ${NB_CORES} \
  && make install \

# compile mediainfo
  && cd /tmp \
  && curl -Lk -o /tmp/libmediainfo.tar.xz "https://mediaarea.net/download/binary/libmediainfo0/${MEDIAINFO_VER}/MediaInfo_DLL_${MEDIAINFO_VER}_GNU_FromSource.tar.xz" \
  && curl -Lk -o /tmp/mediainfo.tar.xz "https://mediaarea.net/download/binary/mediainfo/${MEDIAINFO_VER}/MediaInfo_CLI_${MEDIAINFO_VER}_GNU_FromSource.tar.xz" \
  && mkdir -p /tmp/libmediainfo /tmp/mediainfo \
  && tar Jxf /tmp/libmediainfo.tar.xz -C /tmp/libmediainfo --strip-components=1 \
  && tar Jxf /tmp/mediainfo.tar.xz -C /tmp/mediainfo --strip-components=1 \
  && cd /tmp/libmediainfo \
  && ./SO_Compile.sh \
  && cd /tmp/libmediainfo/ZenLib/Project/GNU/Library \
  && make install \
  && cd /tmp/libmediainfo/MediaInfoLib/Project/GNU/Library \
  && make install \
  && cd /tmp/mediainfo \
  && ./CLI_Compile.sh \
  && cd /tmp/mediainfo/MediaInfo/Project/GNU/CLI \
  && make install \

# Set-up permissions
  && chown -R rtorrent:rtorrent /home/rtorrent/ /var/tmp/nginx  \

# cleanup
  && strip -s /usr/local/bin/mediainfo \
  && strip -s /usr/local/bin/mktorrent \
  && strip -s /usr/local/bin/rtorrent \
  && strip -s /usr/local/bin/xmlrpc \
  && apk del --purge build-dependencies \
  && rm -rf /var/cache/apk/* /tmp/* \
  && rm -rf /usr/local/include /usr/local/share

# Copy startup shells
COPY sh/* /usr/local/bin/

# Copy configuration files

# Set-up php-fpm
COPY config/php-fpm7_www.conf /etc/php7/php-fpm.d/www.conf
# Set-up nginx
COPY config/nginx.conf /etc/nginx/nginx.conf
# Configure supervisor
RUN sed -i -e "s/loglevel=info/loglevel=error/g" /etc/supervisord.conf
COPY config/rtorrentvpn_supervisord.conf /etc/supervisor.d/rtorrentvpn.ini

# Set-up rTorrent
COPY config/rtorrent.rc /home/rtorrent/rtorrent.rc

VOLUME /data /config

CMD ["supervisord", "--nodaemon", "--configuration", "/etc/supervisord.conf"]
