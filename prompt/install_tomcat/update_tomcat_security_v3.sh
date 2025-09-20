#!/bin/bash

# =============================================================================
# Tomcat Security Hardening Script for Rocky Linux
# Description: Diagnose and apply security configurations for Tomcat
# Author: Security Automation Script
# Version: 1.0
# =============================================================================

# Global variables
SCRIPT_NAME="$(basename "$0")"
DEBUG_MODE=false
LOG_FILE=""
TOMCAT_HOME="/was/tomcat/apache-tomcat-9.0.109"  # 사용자가 실제 Tomcat 경로로 수정
DATE_FORMAT="%Y-%m-%d %H:%M:%S"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Security check results
declare -A SECURITY_STATUS=(
    ["server_header"]="unknown"
    ["http_errors"]="unknown"
    ["http_methods"]="unknown"
    ["sample_apps"]="unknown"
    ["tomcat_users"]="unknown"
)

# =============================================================================
# Utility Functions
# =============================================================================

print_usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

OPTIONS:
    --debug         Enable debug mode with verbose output
    --log-file      Specify custom log file path (default: /tmp/tomcat_security_YYYYMMDD_HHMMSS.log)
    --help, -h      Show this help message

DESCRIPTION:
    This script diagnoses and hardens Tomcat security configurations including:
    - Server header hiding
    - HTTP error page consolidation
    - Dangerous HTTP methods blocking
    - Sample application removal
    - Tomcat users file cleanup

EXAMPLES:
    $SCRIPT_NAME
    $SCRIPT_NAME --debug
    $SCRIPT_NAME --log-file /var/log/tomcat_security.log --debug

EOF
}

log_message() {
    local level="$1"
    local message="$2"
    local color=""
    local timestamp=$(date +"$DATE_FORMAT")

    case "$level" in
        "ERROR")   color="$RED" ;;
        "WARN")    color="$YELLOW" ;;
        "INFO")    color="$GREEN" ;;
        "DEBUG")   color="$CYAN" ;;
        "SUCCESS") color="$GREEN" ;;
        *)         color="$WHITE" ;;
    esac

    local formatted_msg="[$timestamp] [$level] $message"

    # Print to console with color
    echo -e "${color}${formatted_msg}${NC}"

    # Save to log file without color codes
    if [[ -n "$LOG_FILE" ]]; then
        echo "$formatted_msg" >> "$LOG_FILE"
    fi
}

debug_log() {
    if [[ "$DEBUG_MODE" == true ]]; then
        log_message "DEBUG" "$1"
    fi
}

error_exit() {
    log_message "ERROR" "$1"
    exit 1
}

create_backup() {
    local source_file="$1"
    local backup_file="${source_file}.backup.$(date +%Y%m%d_%H%M%S)"

    if [[ -f "$source_file" ]]; then
        cp "$source_file" "$backup_file"
        debug_log "Created backup: $backup_file"
        return 0
    fi
    return 1
}

# =============================================================================
# Discovery Functions
# =============================================================================

find_tomcat_installation() {
    log_message "INFO" "Validating Tomcat installation at $TOMCAT_HOME..."

    if [[ ! -d "$TOMCAT_HOME" ]]; then
        error_exit "Tomcat installation not found at $TOMCAT_HOME"
    fi

    log_message "SUCCESS" "Found Tomcat installation: $TOMCAT_HOME"
    debug_log "Tomcat version: $(basename "$TOMCAT_HOME" | sed 's/apache-tomcat-//')"

    # Validate required directories
    local required_dirs=("conf" "webapps" "bin")
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$TOMCAT_HOME/$dir" ]]; then
            error_exit "Required directory $TOMCAT_HOME/$dir not found"
        fi
        debug_log "Validated directory: $TOMCAT_HOME/$dir"
    done
}

# =============================================================================
# Security Diagnosis Functions
# =============================================================================

check_server_header() {
    local server_xml="$TOMCAT_HOME/conf/server.xml"
    debug_log "Checking server header configuration in $server_xml"

    if [[ ! -f "$server_xml" ]]; then
        SECURITY_STATUS["server_header"]="missing_file"
        return 1
    fi

    # Count total Connector elements
    local total_connectors=$(grep -c '<Connector' "$server_xml" 2>/dev/null)
    if [[ $total_connectors -eq 0 ]]; then
        SECURITY_STATUS["server_header"]="no_connectors"
        return 1
    fi

    # Count Connector elements with server="" attribute
    local secure_connectors=$(grep -c 'server=""' "$server_xml" 2>/dev/null)

    if [[ $secure_connectors -eq $total_connectors ]]; then
        SECURITY_STATUS["server_header"]="secure"
        debug_log "All $total_connectors Connector elements have server=\"\" attribute"
        return 0
    else
        SECURITY_STATUS["server_header"]="vulnerable"
        debug_log "Only $secure_connectors out of $total_connectors Connector elements have server=\"\" attribute"
        return 1
    fi
}

check_http_errors() {
    local web_xml="$TOMCAT_HOME/conf/web.xml"
    debug_log "Checking HTTP error configuration in $web_xml"

    if [[ ! -f "$web_xml" ]]; then
        SECURITY_STATUS["http_errors"]="missing_file"
        return 1
    fi

    # Check for error-page configurations
    local error_count=$(grep -c "<error-page>" "$web_xml" 2>/dev/null )

    if [[ $error_count -gt 0 ]]; then
        SECURITY_STATUS["http_errors"]="configured"
        debug_log "Found $error_count error-page configurations"
        return 0
    else
        SECURITY_STATUS["http_errors"]="not_configured"
        return 1
    fi
}

check_http_methods() {
    local web_xml="$TOMCAT_HOME/conf/web.xml"
    debug_log "Checking HTTP methods restriction in $web_xml"

    if [[ ! -f "$web_xml" ]]; then
        SECURITY_STATUS["http_methods"]="missing_file"
        return 1
    fi

    # Check for security-constraint with http-method restrictions
    if grep -A 20 "<security-constraint>" "$web_xml" 2>/dev/null | grep -q "<http-method>"; then
        SECURITY_STATUS["http_methods"]="restricted"
        return 0
    else
        SECURITY_STATUS["http_methods"]="not_restricted"
        return 1
    fi
}

check_sample_apps() {
    local webapps_dir="$TOMCAT_HOME/webapps"
    debug_log "Checking for sample applications in $webapps_dir"

    if [[ ! -d "$webapps_dir" ]]; then
        SECURITY_STATUS["sample_apps"]="missing_directory"
        return 1
    fi

    local sample_apps=("examples" "docs" "manager" "host-manager")
    local found_apps=()

    for app in "${sample_apps[@]}"; do
        if [[ -d "$webapps_dir/$app" ]]; then
            found_apps+=("$app")
            debug_log "Found sample app: $app"
        fi
    done

    if [[ ${#found_apps[@]} -gt 0 ]]; then
        SECURITY_STATUS["sample_apps"]="present"
        return 1
    else
        SECURITY_STATUS["sample_apps"]="removed"
        return 0
    fi
}

check_tomcat_users() {
    local tomcat_users="$TOMCAT_HOME/conf/tomcat-users.xml"
    debug_log "Checking tomcat-users.xml file: $tomcat_users"

    if [[ -f "$tomcat_users" ]]; then
        SECURITY_STATUS["tomcat_users"]="exists"
        return 1
    else
        SECURITY_STATUS["tomcat_users"]="not_exists"
        return 0
    fi
}

run_security_diagnosis() {
    log_message "INFO" "Running security diagnosis..."

    check_server_header
    check_http_errors
    check_http_methods
    check_sample_apps
    check_tomcat_users

    log_message "INFO" "Security diagnosis completed"
}

print_diagnosis_results() {
    echo
    log_message "INFO" "=== SECURITY DIAGNOSIS RESULTS ==="

    # Server Header
    case "${SECURITY_STATUS["server_header"]}" in
        "secure")
            log_message "SUCCESS" "✓ Server header is properly hidden"
            ;;
        "vulnerable")
            log_message "WARN" "✗ Server header is exposed"
            ;;
        "missing_file")
            log_message "ERROR" "✗ server.xml file not found"
            ;;
        "no_connectors")
            log_message "WARN" "✗ No Connector elements found in server.xml"
            ;;
    esac

    # HTTP Errors
    case "${SECURITY_STATUS["http_errors"]}" in
        "configured")
            log_message "SUCCESS" "✓ HTTP error pages are configured"
            ;;
        "not_configured")
            log_message "WARN" "✗ HTTP error pages not configured"
            ;;
        "missing_file")
            log_message "ERROR" "✗ web.xml file not found"
            ;;
    esac

    # HTTP Methods
    case "${SECURITY_STATUS["http_methods"]}" in
        "restricted")
            log_message "SUCCESS" "✓ Dangerous HTTP methods are restricted"
            ;;
        "not_restricted")
            log_message "WARN" "✗ Dangerous HTTP methods are not restricted"
            ;;
        "missing_file")
            log_message "ERROR" "✗ web.xml file not found"
            ;;
    esac

    # Sample Apps
    case "${SECURITY_STATUS["sample_apps"]}" in
        "removed")
            log_message "SUCCESS" "✓ Sample applications are removed"
            ;;
        "present")
            log_message "WARN" "✗ Sample applications are present"
            ;;
        "missing_directory")
            log_message "ERROR" "✗ webapps directory not found"
            ;;
    esac

    # Tomcat Users
    case "${SECURITY_STATUS["tomcat_users"]}" in
        "not_exists")
            log_message "SUCCESS" "✓ tomcat-users.xml file is removed"
            ;;
        "exists")
            log_message "WARN" "✗ tomcat-users.xml file exists"
            ;;
    esac

    echo
}

# =============================================================================
# Security Hardening Functions
# =============================================================================

harden_server_header() {
    if [[ "${SECURITY_STATUS["server_header"]}" == "secure" ]]; then
        log_message "INFO" "Server header is already secure, skipping..."
        return 0
    fi

    local server_xml="$TOMCAT_HOME/conf/server.xml"
    log_message "INFO" "Hardening server header in $server_xml"

    create_backup "$server_xml"

    # First, remove all existing server attributes (any value)
    sed -i 's/[[:space:]]*server="[^"]*"//g' "$server_xml"
    
    # Then, add server="" attribute to all Connector elements
    sed -i ':a;N;$!ba;s/<Connector\([^>]*\)>/<Connector server=""\1>/g' "$server_xml"

    log_message "SUCCESS" "Server header hardening completed"
}

harden_http_errors() {
    if [[ "${SECURITY_STATUS["http_errors"]}" == "configured" ]]; then
        log_message "INFO" "HTTP error pages are already configured, skipping..."
        return 0
    fi

    local web_xml="$TOMCAT_HOME/conf/web.xml"
    log_message "INFO" "Configuring HTTP error pages in $web_xml"

    create_backup "$web_xml"

    # Create error.html file
    local error_page="$TOMCAT_HOME/webapps/ROOT/error.html"
    mkdir -p "$(dirname "$error_page")"

    cat > "$error_page" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Error</title>
    <meta charset="UTF-8">
</head>
<body>
    <h1>Access Error</h1>
    <p>An error has occurred. Please contact the administrator.</p>
</body>
</html>
EOF
    # Add error page configurations to web.xml
    sed -i '/<\/web-app>/i \
    <!-- Custom error pages -->\
    <error-page>\
        <error-code>400</error-code>\
        <location>/error.html</location>\
    </error-page>\
    <error-page>\
        <error-code>401</error-code>\
        <location>/error.html</location>\
    </error-page>\
    <error-page>\
        <error-code>403</error-code>\
        <location>/error.html</location>\
    </error-page>\
    <error-page>\
        <error-code>404</error-code>\
        <location>/error.html</location>\
    </error-page>\
    <error-page>\
        <error-code>500</error-code>\
        <location>/error.html</location>\
    </error-page>\
    <error-page>\
        <exception-type>java.lang.Throwable</exception-type>\
        <location>/error.html</location>\
    </error-page>' "$web_xml"

    log_message "SUCCESS" "HTTP error pages configuration completed"
}

harden_http_methods() {
    if [[ "${SECURITY_STATUS["http_methods"]}" == "restricted" ]]; then
        log_message "INFO" "HTTP methods are already restricted, skipping..."
        return 0
    fi

    local web_xml="$TOMCAT_HOME/conf/web.xml"
    log_message "INFO" "Restricting dangerous HTTP methods in $web_xml"

    create_backup "$web_xml"

    # Create temporary file with security constraint
    local temp_config="/tmp/security_config_$.xml"
    cat > "$temp_config" << 'EOF'

    <!-- Security: Block dangerous HTTP methods -->
    <security-constraint>
        <web-resource-collection>
            <web-resource-name>Restricted Methods</web-resource-name>
            <url-pattern>/*</url-pattern>
            <http-method>PUT</http-method>
            <http-method>DELETE</http-method>
            <http-method>HEAD</http-method>
            <http-method>OPTIONS</http-method>
            <http-method>TRACE</http-method>
        </web-resource-collection>
        <auth-constraint>
            <role-name>impossible</role-name>
        </auth-constraint>
    </security-constraint>
EOF

    # Insert security constraint before </web-app>
    sed -i "/<\/web-app>/e cat $temp_config" "$web_xml"

    # Clean up temporary file
    rm -f "$temp_config"

    log_message "SUCCESS" "HTTP methods restriction completed"
}

remove_sample_apps() {
    if [[ "${SECURITY_STATUS["sample_apps"]}" == "removed" ]]; then
        log_message "INFO" "Sample applications are already removed, skipping..."
        return 0
    fi

    local webapps_dir="$TOMCAT_HOME/webapps"
    log_message "INFO" "Removing sample applications from $webapps_dir"

    local sample_apps=("examples" "docs" "manager" "host-manager")

    for app in "${sample_apps[@]}"; do
        local app_path="$webapps_dir/$app"
        if [[ -d "$app_path" ]]; then
            rm -rf "$app_path"
            log_message "SUCCESS" "Removed sample app: $app"
        else
            debug_log "Sample app not found: $app"
        fi
    done

    log_message "SUCCESS" "Sample applications removal completed"
}

remove_tomcat_users() {
    if [[ "${SECURITY_STATUS["tomcat_users"]}" == "not_exists" ]]; then
        log_message "INFO" "tomcat-users.xml is already removed, skipping..."
        return 0
    fi

    local tomcat_users="$TOMCAT_HOME/conf/tomcat-users.xml"
    log_message "INFO" "Removing tomcat-users.xml file: $tomcat_users"

    create_backup "$tomcat_users"
    rm -f "$tomcat_users"

    log_message "SUCCESS" "tomcat-users.xml removal completed"
}

apply_security_hardening() {
    log_message "INFO" "Applying security hardening measures..."

    harden_server_header
    harden_http_errors
    harden_http_methods
    remove_sample_apps
    remove_tomcat_users

    log_message "SUCCESS" "Security hardening completed"
}

# =============================================================================
# Main Functions
# =============================================================================

initialize_script() {
    # Set default log file if not specified
    if [[ -z "$LOG_FILE" ]]; then
        LOG_FILE="/tmp/tomcat_security_$(date +%Y%m%d_%H%M%S).log"
    fi

    # Create log file
    touch "$LOG_FILE" 2>/dev/null || error_exit "Cannot create log file: $LOG_FILE"

    log_message "INFO" "Tomcat Security Hardening Script Started"
    log_message "INFO" "Log file: $LOG_FILE"

    if [[ "$DEBUG_MODE" == true ]]; then
        log_message "DEBUG" "Debug mode enabled"
    fi
}

setup_environment() {
    # Check if Tomcat is running
    if pgrep -f "tomcat" > /dev/null 2>&1; then
        log_message "WARN" "Tomcat appears to be running. Consider stopping it before applying changes."
    fi
}

main() {
    initialize_script
    find_tomcat_installation
    setup_environment

    run_security_diagnosis
    print_diagnosis_results

    # Ask for confirmation before applying changes
    echo
    read -p "Do you want to apply security hardening measures? (y/N): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        apply_security_hardening
        echo
        log_message "INFO" "Re-running diagnosis to verify changes..."
        run_security_diagnosis
        print_diagnosis_results

        log_message "SUCCESS" "Tomcat security hardening completed successfully!"
    else
        log_message "INFO" "Security hardening cancelled by user"
    fi

    echo
    log_message "INFO" "Script execution completed. Log file: $LOG_FILE"
}

# =============================================================================
# Script Entry Point
# =============================================================================

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --debug)
            DEBUG_MODE=true
            shift
            ;;
        --log-file)
            LOG_FILE="$2"
            shift 2
            ;;
        --help|-h)
            print_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Check if script is run as root (recommended)
if [[ $EUID -ne 0 ]]; then
    log_message "WARN" "This script is not running as root. Some operations may fail."
fi

# Run main function
main
