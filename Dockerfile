FROM registry.gitlab.com/gainde2k/odoo:latest
# Switch to root to install dependencies
USER root

# Build args for all configuration variables
ARG OPENAI_API_KEY
ARG DB_HOST
ARG DB_PORT
ARG DB_USER
ARG DB_PASSWORD
ARG DB_NAME
ARG PGPASSWORD
ARG ODOO_DB
ARG ODOO_USERNAME
ARG ADMIN_PASSWD
ARG PG_URI
ARG WAVE_CHECKOUT_API_KEY
ARG WAVE_PAYOUT_API_KEY
ARG WAVE_BALANCE_API_KEY
ARG WAVE_PAYMENT_RECEIVED_SHARED_SECRET
ARG SERVER_URL
ARG META_VERIFY_TOKEN
ARG META_ACCESS_TOKEN
ARG WHATSAPP_PHONE_NUMBER
ARG WHATSAPP_PHONE_NUMBER_ID
ARG WHATSAPP_BUSINESS_ACCOUNT_ID
ARG META_BASE_API_URL
ARG WHATSAPP_FLOW_PRIVATE_KEY
ARG DULAYNI_API_KEY
ARG AGENTIC_API_KEY
ARG AGENTIC_BASE_URL
ARG DB_URI
ARG DEFAULT_ADMIN_PHONE
ARG DEFAULT_COMPANY_EMAIL
ARG DEFAULT_COMPANY_PHONE

# Environment variables for runtime
ENV OPENAI_API_KEY=${OPENAI_API_KEY}
ENV DB_HOST=${DB_HOST}
ENV DB_PORT=${DB_PORT}
ENV DB_USER=${DB_USER}
ENV DB_PASSWORD=${DB_PASSWORD}
ENV DB_NAME=${DB_NAME}
ENV PGPASSWORD=${PGPASSWORD}
ENV ODOO_DB=${ODOO_DB}
ENV ODOO_USERNAME=${ODOO_USERNAME}
ENV ADMIN_PASSWD=${ADMIN_PASSWD}
ENV PG_URI=${PG_URI}
ENV WAVE_CHECKOUT_API_KEY=${WAVE_CHECKOUT_API_KEY}
ENV WAVE_PAYOUT_API_KEY=${WAVE_PAYOUT_API_KEY}
ENV WAVE_BALANCE_API_KEY=${WAVE_BALANCE_API_KEY}
ENV WAVE_PAYMENT_RECEIVED_SHARED_SECRET=${WAVE_PAYMENT_RECEIVED_SHARED_SECRET}
ENV SERVER_URL=${SERVER_URL}
ENV META_VERIFY_TOKEN=${META_VERIFY_TOKEN}
ENV META_ACCESS_TOKEN=${META_ACCESS_TOKEN}
ENV WHATSAPP_PHONE_NUMBER=${WHATSAPP_PHONE_NUMBER}
ENV WHATSAPP_PHONE_NUMBER_ID=${WHATSAPP_PHONE_NUMBER_ID}
ENV WHATSAPP_BUSINESS_ACCOUNT_ID=${WHATSAPP_BUSINESS_ACCOUNT_ID}
ENV META_BASE_API_URL=${META_BASE_API_URL}
ENV WHATSAPP_FLOW_PRIVATE_KEY=${WHATSAPP_FLOW_PRIVATE_KEY}
ENV DULAYNI_API_KEY=${DULAYNI_API_KEY}
ENV AGENTIC_API_KEY=${AGENTIC_API_KEY}
ENV AGENTIC_BASE_URL=${AGENTIC_BASE_URL}
ENV DB_URI=${DB_URI}
ENV DEFAULT_ADMIN_PHONE=${DEFAULT_ADMIN_PHONE}
ENV DEFAULT_COMPANY_EMAIL=${DEFAULT_COMPANY_EMAIL}
ENV DEFAULT_COMPANY_PHONE=${DEFAULT_COMPANY_PHONE}

# Cache busting: separate COPY for requirements
COPY ./requirements.txt /tmp/requirements.txt

# Install OS-level dependencies (including envsubst and gosu)
RUN apt-get update && \
    apt-get install -y \
    iputils-ping \
    postgresql-client \
    git \
    gettext-base \
    gosu \
    curl \
    locales && \
    rm -rf /var/lib/apt/lists/*

# Fix locale settings
RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
    locale-gen en_US.UTF.8

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# Install PDF utilities
RUN apt-get update && apt-get install -y \
    poppler-utils && \
    rm -rf /var/lib/apt/lists/*

# Create log directory with proper permissions BEFORE Python installation
RUN mkdir -p /var/log/odoo && \
    chown -R odoo:odoo /var/log/odoo && \
    chmod -R 755 /var/log/odoo

# Install Python dependencies
RUN --mount=type=cache,target=/root/.cache \
    set -x && \
    echo "Installing requirements from /tmp/requirements.txt:" && \
    cat /tmp/requirements.txt && \
    pip3 install \
        --verbose \
        --break-system-packages \
        --no-cache-dir \
        --ignore-installed \
        -r /tmp/requirements.txt

# Create ALL necessary directories that are in addons_path
RUN mkdir -p /mnt/social_api /mnt/oca-rest-framework /mnt/oca-web-api /mnt/setup_odoo /mnt/oca-dms /mnt/gainde /mnt/extra-addons && \
    chown -R odoo:odoo /mnt && \
    chown -R odoo:odoo /var/lib/odoo

# COPY ACTUAL MODULE CODE to the paths specified in addons_path
COPY --chown=odoo:odoo ./addons/gainde /mnt/gainde

# Also copy to extra-addons as backup location
COPY --chown=odoo:odoo ./addons /mnt/extra-addons

# Verify the modules were copied correctly
RUN echo "=== Verifying module copy ===" && \
    echo "Social API modules:" && ls -la /mnt/social_api/ && \
    echo "Setup Odoo modules:" && ls -la /mnt/setup_odoo/ && \
    echo "Extra addons structure:" && find /mnt/extra-addons -maxdepth 2 -type d | head -20

# Copy scripts and private key
COPY ./setup_odoo_modules.sh /setup_odoo_modules.sh

COPY ./entrypoint.sh /entrypoint.sh

# Make scripts executable
RUN chmod +x /entrypoint.sh /setup_odoo_modules.sh

# Set the entrypoint (runs as root, then switches to odoo user)
ENTRYPOINT ["/entrypoint.sh"]

# Default command - now simplified since setup happens in entrypoint
CMD ["odoo", "-c", "/etc/odoo/odoo.conf"]