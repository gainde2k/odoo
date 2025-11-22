#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
echo_success() { echo -e "${GREEN}✅ $1${NC}"; }
echo_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
echo_error() { echo -e "${RED}❌ $1${NC}"; }

echo "=== Starting Odoo Configuration Generation ==="

# Set defaults
DB_HOST=${DB_HOST:-"db"}
DB_PORT=${DB_PORT:-"5432"}
DB_USER=${DB_USER:-"odoo"}
DB_PASSWORD=${DB_PASSWORD:-"odoo"}
DB_NAME=${DB_NAME:-"odoo"}
ADMIN_PASSWD=${ADMIN_PASSWD:-"kilifa"}

echo "Using DB_HOST=${DB_HOST}, DB_PORT=${DB_PORT}"

# ============= Fix log directory permissions FIRST =============
echo "=== Fixing log directory permissions ==="
echo "Ensuring /var/log/odoo is owned by odoo user..."
mkdir -p /var/log/odoo
chown -R odoo:odoo /var/log/odoo
chmod -R 755 /var/log/odoo
echo "Log directory permissions fixed."

# ============= Create symbolic link for Docker logs =============
echo "=== Creating symbolic link for Docker logs ==="
# Remove existing log file if it exists
rm -f /var/log/odoo/odoo.log
# Create symbolic link to stdout for Docker logging
ln -sf /dev/stdout /var/log/odoo/odoo.log
chown -h odoo:odoo /var/log/odoo/odoo.log
echo "Symbolic link created for Docker logs"

# ============= Fix filestore permissions =============
echo "=== Fixing filestore permissions ==="
echo "Ensuring /var/lib/odoo is owned by odoo user..."
chown -R odoo:odoo /var/lib/odoo
chmod -R 755 /var/lib/odoo
echo "Filestore permissions fixed."

# Create config file - KEEP original addons_path but ensure directories exist
echo "[options]" > /etc/odoo/odoo.conf
echo "addons_path = /mnt/enterprise,/mnt/oca-rest-framework,/mnt/oca-web-api,/mnt/setup_odoo,/mnt/oca-dms,/mnt/gainde" >> /etc/odoo/odoo.conf
echo "data_dir = /var/lib/odoo" >> /etc/odoo/odoo.conf
echo "admin_passwd = ${ADMIN_PASSWD}" >> /etc/odoo/odoo.conf
# REMOVED: logfile directive - using symbolic link instead
echo "log_handler = [':INFO']" >> /etc/odoo/odoo.conf
echo "db_host = ${DB_HOST}" >> /etc/odoo/odoo.conf
echo "db_port = ${DB_PORT}" >> /etc/odoo/odoo.conf
echo "db_user = ${DB_USER}" >> /etc/odoo/odoo.conf
echo "db_password = ${DB_PASSWORD}" >> /etc/odoo/odoo.conf
# echo "db_name = ${DB_NAME}" >> /etc/odoo/odoo.conf
echo "" >> /etc/odoo/odoo.conf
echo "; Time limits in seconds" >> /etc/odoo/odoo.conf
echo "limit_time_real = 3600" >> /etc/odoo/odoo.conf
echo "limit_time_cpu = 3600" >> /etc/odoo/odoo.conf

# Fix config permissions
chown odoo:odoo /etc/odoo/odoo.conf
chmod 644 /etc/odoo/odoo.conf

echo "Generated config:"
cat /etc/odoo/odoo.conf

# ============= Module Setup Integration =============
# Function to run as odoo user
run_as_odoo() {
    if [ "$(id -u)" = "0" ]; then
        # Running as root, switch to odoo user
        gosu odoo "$@"
    else
        # Already running as odoo user
        exec "$@"
    fi
}

# Environment setup for module installation
export PGPASSWORD="${DB_PASSWORD}"

# Copy setup script to accessible location
if [ -f "/mnt/extra-addons/setup_odoo_modules.sh" ]; then
    cp /mnt/extra-addons/setup_odoo_modules.sh /tmp/setup_odoo_modules.sh
    chmod +x /tmp/setup_odoo_modules.sh
    chown odoo:odoo /tmp/setup_odoo_modules.sh
elif [ -f "/setup_odoo_modules.sh" ]; then
    cp /setup_odoo_modules.sh /tmp/setup_odoo_modules.sh
    chmod +x /tmp/setup_odoo_modules.sh
    chown odoo:odoo /tmp/setup_odoo_modules.sh
fi

# Handle different execution modes
case "$1" in
    odoo)
        echo_info "Starting Odoo with module setup..."
        
        # Check if we should run module setup
        if [ "${SKIP_MODULE_SETUP:-false}" != "true" ]; then
            echo_info "Running module setup script..."
            if [ -f "/tmp/setup_odoo_modules.sh" ]; then
                # Run setup script as odoo user
                run_as_odoo /tmp/setup_odoo_modules.sh
            else
                echo_warning "Module setup script not found - skipping"
            fi
        else
            echo_info "Module setup skipped (SKIP_MODULE_SETUP=true)"
        fi
        
        # Switch to odoo user and start Odoo
        echo_info "Starting Odoo server..."
        exec gosu odoo "$@"
        ;;
    
    setup-modules-only)
        echo_info "Running module setup only..."
        if [ -f "/tmp/setup_odoo_modules.sh" ]; then
            run_as_odoo /tmp/setup_odoo_modules.sh
        else
            echo_error "Module setup script not found!"
            exit 1
        fi
        ;;
    
    setup-core-only)
        echo_info "Running core module setup only..."
        if [ -f "/tmp/setup_odoo_modules.sh" ]; then
            run_as_odoo /tmp/setup_odoo_modules.sh --core-only
        else
            echo_error "Module setup script not found!"
            exit 1
        fi
        ;;
    
    bash|sh)
        echo_info "Starting interactive shell..."
        exec gosu odoo "$@"
        ;;
    
    *)
        # Default case - run original behavior for any other command
        echo "Starting Odoo..."
        exec gosu odoo "$@"
        ;;
esac