FROM m.daocloud.io/docker.io/library/ubuntu:20.04

ENV LANG=C.UTF-8 \
    DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai

ARG FREESWITCH_VERSION=v1.10.12 \
    LIBKS_VERSION=v1.x \
    SIGNALWIRE_C_VERSION=v1.x \
    SOFIA_SIP_VERSION=v1.13.17 \
    SPANDSP_VERSION=0d2e6ac65e0e8f53d652665a743015a88bf048d4 \
    UNIMRCP_VERSION=1.8.0 \
    MOD_UNIMRCP_VERSION=5eaae2575b3b0ea2a80f95f3f45c2ba438cd0d2b \
    MOD_TWILIO_STREAM_VERSION=e3ce165541212c49c21e25c7c520536521748e8e

ARG FREESWITCH_DEFAULT_PASSWORD=whosyourdaddy

ARG UBUNTU_APT_MIRROR=mirrors.ustc.edu.cn \
    UBUNTU_APT_SECURITY_MIRROR=mirrors.ustc.edu.cn \
    GITHUB_MIRROR=https://github.com

RUN sed -i "s@//.*archive.ubuntu.com@//${UBUNTU_APT_MIRROR}@g" /etc/apt/sources.list && \
    sed -i "s/security.ubuntu.com/${UBUNTU_APT_SECURITY_MIRROR}/g" /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y build-essential pkg-config uuid-dev zlib1g-dev libjpeg-dev libsqlite3-dev libcurl4-openssl-dev \
                libpcre3-dev libspeexdsp-dev libldns-dev libedit-dev libtiff5-dev yasm libopus-dev libsndfile1-dev unzip \
                libavformat-dev libswscale-dev libavresample-dev liblua5.2-dev liblua5.2-0 cmake libpq-dev \
                unixodbc-dev autoconf automake ntpdate libxml2-dev libpq-dev libpq5 sngrep libshout3-dev libmpg123-dev libmp3lame-dev \
                curl wget vim git netcat && \
    apt-get clean

# install libks
RUN git clone -b ${LIBKS_VERSION} ${GITHUB_MIRROR}/signalwire/libks.git /usr/local/src/libks && \
    cd /usr/local/src/libks && \
    cmake . && \
    make -j$(nproc --all) && make install

# install signalwire-c
RUN git clone -b ${SIGNALWIRE_C_VERSION} ${GITHUB_MIRROR}/signalwire/signalwire-c.git /usr/local/src/signalwire-c && \
    cd /usr/local/src/signalwire-c && \
    cmake . && \
    make -j$(nproc --all) && make install

# install sofia-sip
RUN git clone -b ${SOFIA_SIP_VERSION} ${GITHUB_MIRROR}/freeswitch/sofia-sip.git /usr/local/src/sofia-sip && \
    cd /usr/local/src/sofia-sip && \
    ./bootstrap.sh && ./configure && \
    make -j$(nproc --all) && make install

# install spandsp
RUN git clone --single-branch ${GITHUB_MIRROR}/freeswitch/spandsp.git /usr/local/src/spandsp && \
    cd /usr/local/src/spandsp && \
    git checkout ${SPANDSP_VERSION} && \
    ./bootstrap.sh && ./configure && \
    make -j$(nproc --all) && make install

# install freeswitch
RUN git clone -b ${FREESWITCH_VERSION} --depth 1 ${GITHUB_MIRROR}/signalwire/freeswitch.git /usr/local/src/freeswitch && \
    cd /usr/local/src/freeswitch && \
    ldconfig && \
    ./bootstrap.sh -j && \
    sed -i 's,#formats/mod_shout,formats/mod_shout,g' modules.conf && \
    sed -i 's,#event_handlers/mod_fail2ban,event_handlers/mod_fail2ban,g' modules.conf && \
    ./configure && \
    make -j$(nproc --all) && make install && \
    ln -s /usr/local/freeswitch/conf /etc/freeswitch && \
    ln -s /usr/local/freeswitch/bin/fs_cli /usr/bin/fs_cli && \
    ln -s /usr/local/freeswitch/bin/freeswitch /usr/sbin/freeswitch && \
    cp src/mod/event_handlers/mod_fail2ban/fail2ban.conf.xml /usr/local/freeswitch/conf/autoload_configs/

# install sounds and music for freeswitch
RUN cd /usr/local/src/freeswitch && \
    make cd-sounds-install && \
    make cd-moh-install && \
    rm /usr/local/src/freeswitch/freeswitch-sounds-*.tar.gz

# post-install for freeswitch
RUN cd /usr/local/freeswitch && \
    sed -i "s,default_password=1234,default_password=${FREESWITCH_DEFAULT_PASSWORD},g" conf/vars.xml && \
    sed -i "s,ClueCon,${FREESWITCH_DEFAULT_PASSWORD},g" conf/autoload_configs/event_socket.conf.xml && \
    sed -i '/<\/settings>/i \    <param name="apply-inbound-acl" value="any_v4.auto"\/>' conf/autoload_configs/event_socket.conf.xml && \
    sed -i 's,<!--<load module="mod_shout"/>-->,<load module="mod_shout"/>,g' conf/autoload_configs/modules.conf.xml && \
    sed -i 's,<load module="mod_signalwire"/>,<!--<load module="mod_signalwire"/>-->,g' conf/autoload_configs/modules.conf.xml && \
    sed -i '/<\/modules>/i \    <load module="mod_fail2ban"\/>' conf/autoload_configs/modules.conf.xml && \
    mv conf/sip_profiles/external-ipv6.xml conf/sip_profiles/external-ipv6.xml.disabled && \
    mv conf/sip_profiles/internal-ipv6.xml conf/sip_profiles/internal-ipv6.xml.disabled

# install apr for unimrcp
RUN curl -sS -o /tmp/unimrcp-deps.tar.gz https://www.unimrcp.org/project/component-view/unimrcp-deps-1-6-0-tar-gz/download && \
    tar zxf /tmp/unimrcp-deps.tar.gz -C /usr/local/src --strip-components=2 --wildcards '*/apr' '*/apr-util' && rm /tmp/unimrcp-deps.tar.gz && \
    cd /usr/local/src/apr && \
    ./configure && make -j$(nproc --all) && make install && \
    cd /usr/local/src/apr-util && \
    ./configure --with-apr=/usr/local/src/apr && \
    make -j$(nproc --all) && make install

# install unimrcp for mod_unimrcp
RUN git clone -b unimrcp-${UNIMRCP_VERSION} ${GITHUB_MIRROR}/unispeech/unimrcp /usr/local/src/unimrcp && \
    cd /usr/local/src/unimrcp && \
    ./bootstrap && ./configure && \
    make -j$(nproc --all) && make install

# install mod_unimrcp
RUN git clone ${GITHUB_MIRROR}/freeswitch/mod_unimrcp.git /usr/local/src/mod_unimrcp && \
    cd /usr/local/src/mod_unimrcp && \
    git checkout ${MOD_UNIMRCP_VERSION} && \
    ./bootstrap.sh && PKG_CONFIG_PATH=/usr/local/freeswitch/lib/pkgconfig:/usr/local/unimrcp/lib/pkgconfig ./configure && \
    make -j$(nproc --all) && make install && \
    sed -i '/<\/modules>/i \    <load module="mod_unimrcp"\/>' /usr/local/freeswitch/conf/autoload_configs/modules.conf.xml && \
    mkdir -p /usr/local/freeswitch/conf/mrcp_profiles

# install mod_twilio_stream
RUN git clone ${GITHUB_MIRROR}/somleng/somleng-switch.git /usr/local/src/somleng-switch && \
    cd /usr/local/src/somleng-switch && \
    git checkout ${MOD_TWILIO_STREAM_VERSION} && \
    mkdir -p components/freeswitch/src/mod/mod_twilio_stream/build && \
    cd components/freeswitch/src/mod/mod_twilio_stream/build && \
    cmake -DFREESWITCH_INCLUDE_DIR=/usr/local/freeswitch/include/freeswitch/ .. && \
    make -j$(nproc --all) && make install && \
    sed -i '/<\/modules>/i \    <load module="mod_twilio_stream"\/>' /usr/local/freeswitch/conf/autoload_configs/modules.conf.xml

WORKDIR /usr/local/freeswitch/

CMD ["/usr/local/freeswitch/bin/freeswitch", "-c", "-nonat"]