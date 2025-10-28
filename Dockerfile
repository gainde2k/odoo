FROM odoo:18.0

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
ARG ODOO_PASSWORD
ARG PG_URI
ARG WAVE_CHECKOUT_API_KEY
ARG WAVE_PAYOUT_API_KEY
ARG WAVE_BALANCE_API_KEY
ARG WAVE_PAYMENT_RECEIVED_SHARED_SECRET
ARG SERVER_URL
ARG WHATSAPP_VERIFY_TOKEN
ARG WHATSAPP_ACCESS_TOKEN
ARG WHATSAPP_PHONE_NUMBER
ARG WHATSAPP_PHONE_NUMBER_ID
ARG WHATSAPP_BUSINESS_ACCOUNT_ID
ARG WHATSAPP_BASE_API_URL
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
ENV ODOO_PASSWORD=${ODOO_PASSWORD}
ENV PG_URI=${PG_URI}
ENV WAVE_CHECKOUT_API_KEY=${WAVE_CHECKOUT_API_KEY}
ENV WAVE_PAYOUT_API_KEY=${WAVE_PAYOUT_API_KEY}
ENV WAVE_BALANCE_API_KEY=${WAVE_BALANCE_API_KEY}
ENV WAVE_PAYMENT_RECEIVED_SHARED_SECRET=${WAVE_PAYMENT_RECEIVED_SHARED_SECRET}
ENV SERVER_URL=${SERVER_URL}
ENV WHATSAPP_VERIFY_TOKEN=${WHATSAPP_VERIFY_TOKEN}
ENV WHATSAPP_ACCESS_TOKEN=${WHATSAPP_ACCESS_TOKEN}
ENV WHATSAPP_PHONE_NUMBER=${WHATSAPP_PHONE_NUMBER}
ENV WHATSAPP_PHONE_NUMBER_ID=${WHATSAPP_PHONE_NUMBER_ID}
ENV WHATSAPP_BUSINESS_ACCOUNT_ID=${WHATSAPP_BUSINESS_ACCOUNT_ID}
ENV WHATSAPP_BASE_API_URL=${WHATSAPP_BASE_API_URL}
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

# Set permissions and prepare addons directory
RUN mkdir -p /mnt/extra-addons && \
    chown -R odoo:odoo /mnt/extra-addons && \
    chown -R odoo:odoo /var/lib/odoo && \
    chsh -s /bin/bash odoo || usermod -s /bin/bash odoo

RUN mkdir -p /mnt && \
    chown -R odoo:odoo /mnt

# Copy addons, scripts and entrypoint
COPY --chown=odoo:odoo ./addons /mnt/extra-addons
COPY ./setup_odoo_modules.sh /setup_odoo_modules.sh
COPY ./whatsapp_flow_private_key.pem /mnt/extra-addons/whatsapp_flow_private_key.pem

# Fix private key permissions - ADD THESE LINES
RUN chown odoo:odoo /mnt/extra-addons/whatsapp_flow_private_key.pem && \
    chmod 600 /mnt/extra-addons/whatsapp_flow_private_key.pem

COPY ./entrypoint.sh /entrypoint.sh

# Make scripts executable
RUN chmod +x /entrypoint.sh /setup_odoo_modules.sh

# Don't switch to odoo user yet - let entrypoint handle it
# USER odoo

# Set the entrypoint (runs as root, then switches to odoo user)
ENTRYPOINT ["/entrypoint.sh"]

# Default command - now simplified since setup happens in entrypoint
CMD ["odoo", "-c", "/etc/odoo/odoo.conf"]
