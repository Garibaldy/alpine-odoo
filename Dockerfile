# Copyright 2017-TODAY Benoit "XtremXpert" Vezina
# License MIT (https://opensource.org/licenses/MIT).

# Much of this taken from https://github.com/LasLabs/docker-odoo/blob/master/Dockerfile

# Update to a newer alpine version
FROM python:2-alpine3.6

MAINTAINER "Benoît Vézina" <benoit@xtremxpert.com>

ARG ODOO_VERSION="10.0"
ARG ODOO_REPO="odoo/odoo"
ARG ODOO_CONFIG_FILE="odoo.conf"
ARG ODOO_CONFIG_DIR="/etc/odoo"
ARG WKHTMLTOX_VERSION="0.12"
ARG WKHTMLTOX_SUBVERSION="4"

ENV ODOO_LOG="/var/log/odoo.log"
ENV ODOO_CONFIG="${ODOO_CONFIG_DIR}/${ODOO_CONFIG_FILE}"
ENV WKHTMLTOX_RELEASE="${WKHTMLTOX_VERSION}.${WKHTMLTOX_SUBVERSION}"
ENV WKHTMLTOX_URI="http://download.gna.org/wkhtmltopdf/${WKHTMLTOX_VERSION}/${WKHTMLTOX_RELEASE}/wkhtmltox-${WKHTMLTOX_RELEASE}_linux-generic-amd64.tar.xz"

# For stable 10.0
ENV ODOO_URI="https://github.com/${ODOO_REPO}/archive/${ODOO_VERSION}.tar.gz"
# For Nightly 11.0 alpha
#ENV ODOO_URI="https://nightly.odoo.com/master/nightly/src/odoo_11.0alpha1.latest.tar.gz"

# https://github.com/OCA/maintainer-quality-tools/pull/404
ENV MQT_URI="https://github.com/LasLabs/maintainer-quality-tools/archive/bugfix/script-shebang.tar.gz"

# Set this as an env var instead of arg so its avail to entrypoint
ENV ODOO_VERSION=$ODOO_VERSION

# Other requirements and recommendations to run Odoo
# See https://github.com/$ODOO_SOURCE/blob/$ODOO_VERSION/debian/control
RUN apk add --no-cache \
        git \
        ghostscript \
        icu \
        libev \
        nodejs \
        nodejs-npm \
        openssl \
##        postgresql-client \
#        postgresql-libs \
        poppler-utils \
        ruby \
        su-exec

# Special case for wkhtmltox
# HACK https://github.com/wkhtmltopdf/wkhtmltopdf/issues/3265
# Idea from https://hub.docker.com/r/loicmahieu/alpine-wkhtmltopdf/
# Use prepackaged wkhtmltopdf and wrap it with a dummy X server
RUN apk add --no-cache --repository http://dl-cdn.alpinelinux.org/alpine/edge/testing wkhtmltopdf
RUN apk add --no-cache xvfb ttf-dejavu ttf-freefont fontconfig dbus
COPY bin/wkhtmltox.sh /usr/local/bin/wkhtmltoimage
COPY python-ldap.patch /tmp/setup.cfg.diff
RUN ln /usr/local/bin/wkhtmltoimage /usr/local/bin/wkhtmltopdf

# Requirements to build Odoo dependencies
RUN apk add --no-cache --virtual .build-deps \
    curl \
    # Common to all Python packages
    build-base \
    tar \
    python-dev \
    # lxml
    libxml2-dev \
    libxslt-dev \
    # Pillow
    freetype-dev \
    jpeg-dev \
    lcms2-dev \
    openjpeg-dev \
    tcl-dev \
    tiff-dev \
    tk-dev \
    zlib-dev \
    # psutil
    linux-headers \
    # psycopg2
# postgresql is needed for pgdump
    postgresql \
    postgresql-dev \
    # python-ldap
    openldap-dev \
    # Sass, compass
    libffi-dev \
    ruby-dev \
    # CSS preprocessors
    && gem install --clear-sources --no-document bootstrap-sass compass \
    && npm install -g less \
    # Build and install Odoo dependencies with pip
    # HACK Some modules cannot be installed with PYTHONOPTIMIZE=2
    && PYTHONOPTIMIZE=1 pip install --no-cache-dir \
        # HACK https://github.com/giampaolo/psutil/issues/948
        psutil==2.2.0 \
        # HACK https://github.com/erocarrera/pydot/issues/145
        pydot==1.0.2 \
        # HACK https://github.com/psycopg/psycopg2/commit/37d80f2c0325951d3ee6b07caf7d343d4a97a23d
        # TODO Remove in psycopg2>=2.6
        psycopg2==2.5.4 \
        # HACK https://github.com/eventable/vobject/pull/19
        # TODO Remove in vobject>=0.9.3
        vobject==0.6.6

# Install Odoo
RUN adduser -D odoo \
	&& mkdir -p /opt/odoo \
    && curl -sL "$ODOO_URI" | tar xz -C /opt/odoo --strip 1 \
	&& cd /opt/odoo \
	&& pip install --no-cache-dir -r ./requirements.txt \
    && pip install --no-cache-dir . \
    && chown -R odoo /opt/odoo \
	&& mkdir -p \
		/etc/odoo \
        /mnt/addons \
        /opt/addons \
        /opt/community \
        /var/lib/odoo \
        /var/log/odoo \
    && ln -sf /dev/stdout "$ODOO_LOG" \
    && chown odoo -R \
    	/etc/odoo \
        /mnt/addons \
        /opt/addons \
        /opt/community \
        /var/lib/odoo \
        /var/log/odoo

# Upgrade pillow, old versions cause zlib issues for some reason
RUN CFLAGS="$CFLAGS -L/lib" pip install --no-cache-dir --upgrade pillow

# OCA Repos
RUN curl -sL "$MQT_URI" | tar -xz -C /opt/ \
    && ln -s /opt/maintainer-quality-tools-*/travis/clone_oca_dependencies /usr/bin \
    && ln -s /opt/maintainer-quality-tools-*/travis/getaddons.py /usr/bin/get_addons \
    && chmod +x /usr/bin/get_addons

# Remove unneeded build dependencies
# Re-enable once better binary dependency resolution
#RUN rm -Rf /tmp/odoo \
#    && cp /usr/bin/pg_dump /tmp \
#    && cp /usr/bin/pg_restore /tmp \
#    && apk del .build-deps \
#    && mv /tmp/pg_dump /usr/bin/pg_dump \
#    && mv /tmp/pg_restore /usr/bin/pg_restore

# WDB debugger
RUN pip install --no-cache-dir wdb

# Other facilities
RUN apk add --no-cache bash gettext postgresql-client
#RUN apk add --no-cache bash gettext
RUN pip install --no-cache-dir openupgradelib

# Copy Entrypoint & Odoo conf
COPY ./docker-entrypoint.sh /docker-entrypoint.sh
#COPY ./etc/odoo-server.conf "$ODOO_CONFIG"
#COPY ./etc/odoo-server.conf /root/etc/odoo/odoo.conf
COPY ./etc/odoo-server.conf /root"$ODOO_CONFIG"

RUN chown odoo /docker-entrypoint.sh \
    && chmod +x /docker-entrypoint.sh \
    && chown odoo -R "$ODOO_CONFIG_DIR"

# Move binary to new location and symlink old
RUN if [ "$ODOO_VERSION" != "10.0" ]; \
    then \
        mv /usr/local/bin/openerp-server /usr/local/bin/odoo && \
        ln -s /usr/local/bin/odoo /usr/local/bin/openerp-server; \
    fi

# Fix stack size overflow
# https://github.com/python-pillow/Pillow/issues/1935
RUN awk '/import odoo/ { print; print "import threading; threading.stack_size(4*80*1024)"; next }1' /usr/local/bin/odoo > /tmp-bin \
    && mv /tmp-bin /usr/local/bin/odoo \
    && chmod +x /usr/local/bin/odoo

# Mount Volumes
VOLUME ["/var/lib/odoo", "/mnt/addons", "/etc/odoo"]

# Expose Odoo services
EXPOSE 8069 8071

# Big hack to fix ldap error from server-tools
# ImportError: Error relocating /usr/local/lib/python2.7/site-packages/_ldap.so: ber_free: symbol not found
RUN cd /tmp \
	&& wget https://pypi.python.org/packages/fc/99/9eed836fe4d916792994838df125da9c25c5f7c31abfbf6f0ab076e5f419/python-ldap-2.4.27.tar.gz \
	&& tar -xvf python-ldap-2.4.27.tar.gz \
	&& cd /tmp/python-ldap-2.4.27 \
	&& patch -i /tmp/setup.cfg.diff setup.cfg \
	&& python setup.py build \
	&& pip uninstall -y python-ldap \
	&& python setup.py install

# Entrypoint & Cmd
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["odoo"]
