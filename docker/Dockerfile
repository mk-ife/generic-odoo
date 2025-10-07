# ---- base stage ----
FROM debian:bookworm-slim AS base

# System-Pakete inkl. wkhtmltopdf & envsubst
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates git tini \
    build-essential python3 python3-dev python3-venv python3-pip \
    libpq-dev libxml2-dev libxslt1-dev libjpeg-dev zlib1g-dev libldap2-dev libsasl2-dev \
    libffi-dev libssl-dev libjpeg62-turbo-dev libtiff6 libopenjp2-7 libfreetype6 liblcms2-2 \
    libwebp7 libharfbuzz0b libfribidi0 libxcb1 \
    fonts-dejavu fonts-liberation \
    gettext-base \
    wkhtmltopdf \
  && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/odoo/src /opt/odoo/custom /opt/odoo/enterprise /opt/odoo/venv \
             /var/lib/odoo /var/log/odoo /etc/odoo \
 && useradd -m -d /opt/odoo -s /bin/bash odoo \
 && chown -R odoo:odoo /opt/odoo /var/lib/odoo /var/log/odoo /etc/odoo

# ---- build stage ----
FROM base AS build
WORKDIR /opt/odoo
ARG ODOO_VERSION=18.0
RUN git clone --depth=1 --branch ${ODOO_VERSION} https://github.com/odoo/odoo.git /opt/odoo/src
RUN python3 -m venv /opt/odoo/venv \
 && . /opt/odoo/venv/bin/activate \
 && pip install --upgrade pip wheel \
 && pip install -r /opt/odoo/src/requirements.txt

# ---- runtime stage ----
FROM base AS runtime
WORKDIR /opt/odoo

# venv + src aus build übernehmen
COPY --from=build /opt/odoo/venv /opt/odoo/venv
COPY --from=build /opt/odoo/src  /opt/odoo/src

# Template & Entrypoint aus Build-Kontext (== docker/) kopieren
COPY odoo.conf.template /etc/odoo/odoo.conf.template
COPY entrypoint.sh      /usr/local/bin/entrypoint.sh

# Rechte & PATH
RUN chmod +x /usr/local/bin/entrypoint.sh \
 && chown -R odoo:odoo /opt/odoo /var/lib/odoo /var/log/odoo /etc/odoo
ENV PATH="/opt/odoo/venv/bin:${PATH}"

USER odoo
EXPOSE 8069
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["python", "/opt/odoo/src/odoo-bin", "-c", "/etc/odoo/odoo.conf"]
