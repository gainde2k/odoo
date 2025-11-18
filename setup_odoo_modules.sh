#!/bin/bash
# setup_odoo_modules.sh - External installation script for Docker environment

set -e  # Exit on any error

# Configuration from environment variables
DB_NAME="${DB_NAME:-odoo}"
DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-odoo}"
DB_PASSWORD="${DB_PASSWORD:-odoo}"
ODOO_CONFIG="/etc/odoo/odoo.conf"

# Core modules to install (in dependency order)
CORE_MODULES=(
    "base"
    "web"
    "contacts"
    "product"
    "account"
    "mail"
)

# Optional custom modules  
CUSTOM_MODULES=(
    "gainde"
)

echo "🚀 Starting Odoo module setup..."
echo "📋 Database: $DB_NAME"
echo "🌐 Host: $DB_HOST:$DB_PORT"

# Function to wait for database
wait_for_db() {
    echo "⏳ Waiting for database connection..."
    local max_tries=30
    local count=0
    
    until PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" >/dev/null 2>&1; do
        count=$((count + 1))
        if [ $count -gt $max_tries ]; then
            echo "❌ Database connection timeout after $max_tries attempts"
            exit 1
        fi
        echo "⏳ Attempt $count/$max_tries - waiting for database..."
        sleep 2
    done
    echo "✅ Database connection established"
}

# Enhanced function to check if module exists in filesystem
module_exists() {
    local module=$1
    
    echo "🔍 Searching for module: $module"
    
    # Check in standard Odoo addons path
    if [ -d "/usr/lib/python3/dist-packages/odoo/addons/$module" ]; then
        echo "✅ Found module $module in standard Odoo addons"
        return 0
    fi
    
    # Comprehensive list of paths to check (including both individual paths and extra-addons)
    local paths=(
        "/mnt/social_api"
        "/mnt/oca-rest-framework"
        "/mnt/oca-web-api"
        "/mnt/setup_odoo"
        "/mnt/oca-dms"
        "/mnt/gainde"
        "/mnt/extra-addons"
        "/mnt/extra-addons/social_api"
        "/mnt/extra-addons/oca/rest-framework"
        "/mnt/extra-addons/oca/web-api"
        "/mnt/extra-addons/oca/dms"
        "/mnt/extra-addons/setup_odoo"
        "/mnt/extra-addons/gainde"
    )
    
    # Check all defined paths
    for path in "${paths[@]}"; do
        if [ -d "$path/$module" ]; then
            echo "✅ Found module $module at: $path/$module"
            return 0
        fi
    done
    
    # Additional check: recursively search in all /mnt subdirectories
    local found_path=$(find /mnt -type d -name "$module" 2>/dev/null | head -1)
    if [ -n "$found_path" ]; then
        echo "✅ Found module $module at: $found_path"
        return 0
    fi
    
    # Final check: look for __manifest__.py in any subdirectory with the module name
    local manifest_path=$(find /mnt -path "*/$module/__manifest__.py" 2>/dev/null | head -1)
    if [ -n "$manifest_path" ]; then
        echo "✅ Found module $module via manifest at: $(dirname $manifest_path)"
        return 0
    fi
    
    echo "❌ Module $module not found in any location"
    return 1
}

# Function to install module safely
install_module() {
    local module=$1
    echo "📦 Installing module: $module"
    
    # Check if module exists first
    if ! module_exists "$module"; then
        echo "❌ Module $module not found in any addons path!"
        return 1
    fi
    
    # Try to install with proper error handling
    if timeout 300 odoo \
        --database="$DB_NAME" \
        --init="$module" \
        --stop-after-init \
        --config="$ODOO_CONFIG" \
        --without-demo=all \
        --log-level=info \
        --no-http; then
        echo "✅ Successfully installed: $module"
        return 0
    else
        echo "❌ Failed to install: $module"
        return 1
    fi
}

# Function to install module with retry
install_module_with_retry() {
    local module=$1
    local max_retries=3
    local count=0
    
    while [ $count -lt $max_retries ]; do
        if install_module "$module"; then
            return 0
        fi
        count=$((count + 1))
        echo "🔄 Retrying $module installation (attempt $count/$max_retries)..."
        sleep 5
    done
    
    echo "❌ Failed to install $module after $max_retries attempts"
    return 1
}

# Function to check if database exists and has been initialized
check_database() {
    echo "🔍 Checking database status..."
    
    # Check if database exists
    if ! PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
        echo "📊 Database $DB_NAME does not exist - will be created by Odoo"
        return 1
    fi
    
    # Check if database has been initialized (has ir_module_module table)
    if PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1 FROM information_schema.tables WHERE table_name='ir_module_module';" | grep -q "1 row"; then
        echo "✅ Database $DB_NAME is initialized"
        return 0
    else
        echo "📊 Database $DB_NAME exists but is not initialized"
        return 1
    fi
}

# Function to verify module installation status
verify_module_installation() {
    echo "🔍 Verifying module installation status..."
    
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" << EOF
SELECT 
    name, 
    state,
    CASE 
        WHEN state = 'installed' THEN '✅'
        WHEN state = 'uninstalled' THEN '❌'
        WHEN state = 'to install' THEN '⏳'
        WHEN state = 'to upgrade' THEN '🔄'
        ELSE '❓'
    END as status
FROM ir_module_module 
WHERE name IN ('contacts', 
                'account',
                'mail',
                'gainde'
            )
ORDER BY name;
EOF
}

# Enhanced pre-flight check for modules
check_modules_available() {
    echo "🔍 Checking if all modules are available..."
    
    local all_modules=("${CORE_MODULES[@]}" "${CUSTOM_MODULES[@]}" "setup_odoo")
    local missing_modules=()
    
    for module in "${all_modules[@]}"; do
        if ! module_exists "$module"; then
            missing_modules+=("$module")
        fi
    done
    
    if [ ${#missing_modules[@]} -gt 0 ]; then
        echo "❌ Missing modules: ${missing_modules[*]}"
        echo "📁 Available modules in /mnt:"
        find /mnt -name "__manifest__.py" | sed 's|/__manifest__.py||' | xargs -I {} basename {} | sort | uniq
        return 1
    fi
    
    return 0
}

# Function to debug module locations
debug_module_locations() {
    echo "🐛 DEBUG: Module location analysis"
    echo "=== Directory structure of /mnt ==="
    find /mnt -type d -name "*" | head -20
    echo "=== All __manifest__.py files found ==="
    find /mnt -name "__manifest__.py" | head -10
}

# Main execution
main() {
    # Wait for database to be ready
    wait_for_db
    
    # Debug: show module locations first
    debug_module_locations
    
    # Pre-flight check
    if ! check_modules_available; then
        echo "❌ Aborting due to missing modules"
        exit 1
    fi
    
    # Check if we need to initialize the database
    if ! check_database; then
        echo "🔧 Initializing database with base module..."
        timeout 300 odoo \
            --database="$DB_NAME" \
            --init=base \
            --stop-after-init \
            --config="$ODOO_CONFIG" \
            --without-demo=all \
            --log-level=warn \
            --logfile=/dev/stdout \
            --no-http
        
        echo "✅ Database initialized"
    fi
    
    # Install core modules
    echo "📋 Installing core modules..."
    for module in "${CORE_MODULES[@]}"; do
        install_module_with_retry "$module" || echo "⚠️  Continuing with remaining modules..."
    done
    
    # Install custom modules
    echo "📋 Installing custom modules..."
    for module in "${CUSTOM_MODULES[@]}"; do
        install_module_with_retry "$module" || echo "⚠️  Continuing with remaining modules..."
    done
    
    # Final update to ensure everything is properly installed
    echo "🔄 Running final update..."
    timeout 300 odoo \
        --database="$DB_NAME" \
        --update=all \
        --stop-after-init \
        --config="$ODOO_CONFIG" \
        --without-demo=all \
        --log-level=warn \
        --logfile=/dev/stdout \
        --no-http || echo "⚠️  Final update had issues - but continuing..."
    
    # Verify installation
    verify_module_installation
    
    echo "✨ Module setup complete!"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [--help|--check-only|--core-only|--verify|--debug]"
        echo "  --help: Show this help"
        echo "  --check-only: Only check database and module status"
        echo "  --core-only: Install only core modules"
        echo "  --verify: Only verify installation status"
        echo "  --debug: Show debug information about module locations"
        exit 0
        ;;
    --check-only)
        wait_for_db
        check_database
        check_modules_available
        exit $?
        ;;
    --core-only)
        # Only install core modules
        CUSTOM_MODULES=()
        main
        ;;
    --verify)
        wait_for_db
        verify_module_installation
        ;;
    --debug)
        debug_module_locations
        ;;
    *)
        main
        ;;
esac