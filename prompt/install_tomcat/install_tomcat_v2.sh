#!/bin/bash
#
# Tomcat 9 Secure Installation Script for Rocky Linux
# Author: System Administrator
# Description: Install and configure Tomcat 9 with security hardening
#

# Global Variables
SCRIPT_NAME="$(basename "$0")"
INSTALL_BASE="/was"
TOMCAT_USER="tomcat"
TOMCAT_GROUP="tomcat"
JAVA_HOME="/usr/lib/jvm/java-11-openjdk"
DEBUG=false
LOG_FILE="/tmp/tomcat9_install_$(date +%Y%m%d_%H%M%S).log"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    local message="$1"
    echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE"
}

log_warn() {
    local message="$1"
    echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
}

log_error() {
    local message="$1"
    echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
}

log_debug() {
    local message="$1"
    if [ "$DEBUG" = true ]; then
        echo -e "${CYAN}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
    fi
}

log_section() {
    local message="$1"
    echo -e "${PURPLE}[SECTION]${NC} $message" | tee -a "$LOG_FILE"
    echo "=================================================" | tee -a "$LOG_FILE"
}

# Function: Check if running as root
check_root() {
    log_section "Checking root privileges"

    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi

    log_info "Root privileges confirmed"
}

# Function: Install Java 11
install_java() {
    log_section "Installing Java 11 OpenJDK"

    # Check if Java is already installed
    if command -v java >/dev/null 2>&1; then
        local java_version=$(java -version 2>&1 | head -n 1 | cut -d'"' -f2)
        log_info "Java is already installed: $java_version"
        return 0
    fi

    log_info "Installing Java 11 OpenJDK..."
    dnf update -y >> "$LOG_FILE" 2>&1
    dnf install -y java-11-openjdk java-11-openjdk-devel >> "$LOG_FILE" 2>&1

    if [ $? -eq 0 ]; then
        log_info "Java 11 OpenJDK installed successfully"
        export JAVA_HOME="$JAVA_HOME"
        echo "export JAVA_HOME=$JAVA_HOME" >> /etc/environment
    else
        log_error "Failed to install Java 11 OpenJDK"
        exit 1
    fi
}

# Function: Create Tomcat user
create_tomcat_user() {
    log_section "Creating Tomcat user and group"

    # Check if group exists
    if ! getent group "$TOMCAT_GROUP" >/dev/null 2>&1; then
        log_info "Creating group: $TOMCAT_GROUP"
        groupadd "$TOMCAT_GROUP"
    else
        log_info "Group $TOMCAT_GROUP already exists"
    fi

    # Check if user exists
    if ! id "$TOMCAT_USER" >/dev/null 2>&1; then
        log_info "Creating user: $TOMCAT_USER"
        useradd -r -g "$TOMCAT_GROUP" -d "$INSTALL_BASE" -s /sbin/nologin "$TOMCAT_USER"
    else
        log_info "User $TOMCAT_USER already exists"
    fi
}

# Function: Install Tomcat 9
install_tomcat() {
    log_section "Installing Tomcat 9"

    # Get latest Tomcat 9 version
    log_info "Fetching latest Tomcat 9 version information..."
    local tomcat_version=$(curl -s https://archive.apache.org/dist/tomcat/tomcat-9/ | grep -o 'v[0-9]\+\.[0-9]\+\.[0-9]\+' | sort -V | tail -1 | sed 's/v//')

    if [ -z "$tomcat_version" ]; then
        # Fallback to known stable version
        tomcat_version="9.0.82"
        log_warn "Could not fetch latest version, using fallback: $tomcat_version"
    else
        log_info "Latest Tomcat 9 version: $tomcat_version"
    fi

    local tomcat_url="https://archive.apache.org/dist/tomcat/tomcat-9/v${tomcat_version}/bin/apache-tomcat-${tomcat_version}.tar.gz"
    local install_dir="${INSTALL_BASE}/apache-tomcat-${tomcat_version}"

    # Create installation directory
    log_info "Creating installation directory: $INSTALL_BASE"
    mkdir -p "$INSTALL_BASE"
    cd "$INSTALL_BASE"

    # Download Tomcat
    log_info "Downloading Tomcat $tomcat_version..."
    log_debug "Download URL: $tomcat_url"
    wget -q "$tomcat_url" -O "apache-tomcat-${tomcat_version}.tar.gz"

    if [ $? -ne 0 ]; then
        log_error "Failed to download Tomcat"
        exit 1
    fi

    # Extract Tomcat
    log_info "Extracting Tomcat archive..."
    tar -xzf "apache-tomcat-${tomcat_version}.tar.gz"
    rm -f "apache-tomcat-${tomcat_version}.tar.gz"

    # Set ownership
    log_info "Setting ownership to $TOMCAT_USER:$TOMCAT_GROUP"
    chown -R "$TOMCAT_USER:$TOMCAT_GROUP" "$install_dir"

    # Set executable permissions
    chmod +x "$install_dir/bin/"*.sh

    # Export global variables for other functions
    export TOMCAT_HOME="$install_dir"
    export TOMCAT_VERSION="$tomcat_version"

    log_info "Tomcat $tomcat_version installed successfully at $install_dir"
}

# Function: Remove server header
remove_server_header() {
    log_section "Configuring server header removal"

    local server_xml="$TOMCAT_HOME/conf/server.xml"
    log_info "Modifying server.xml to hide server header"

    # Backup original file
    cp "$server_xml" "${server_xml}.backup"

    # Add server attribute to Connector elements
    sed -i 's/<Connector port="8080"/<Connector port="8080" server=""/' "$server_xml"
    sed -i 's/<Connector port="8443"/<Connector port="8443" server=""/' "$server_xml"

    log_info "Server header configured to empty string"
}

# Function: Configure error pages
configure_error_pages() {
    log_section "Configuring unified error pages"

    local web_xml="$TOMCAT_HOME/conf/web.xml"
    local webapps_dir="$TOMCAT_HOME/webapps"

    log_info "Creating custom error page"

    # Create ROOT webapp if it doesn't exist
    mkdir -p "$webapps_dir/ROOT"

    # Create error.html
    cat > "$webapps_dir/ROOT/error.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Error</title>
    <meta charset="UTF-8">
    <style>
        body { font-family: Arial, sans-serif; text-align: center; margin-top: 100px; }
        .error { color: #d32f2f; font-size: 24px; }
        .message { color: #666; font-size: 16px; margin-top: 20px; }
    </style>
</head>
<body>
    <div class="error">Application Error</div>
    <div class="message">Please contact the system administrator.</div>
</body>
</html>
EOF

    # Backup web.xml
    cp "$web_xml" "${web_xml}.backup"

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

    log_info "Unified error pages configured"
}

# Function: Remove unnecessary HTTP methods
remove_unnecessary_methods() {
    log_section "Disabling unnecessary HTTP methods"

    local web_xml="$TOMCAT_HOME/conf/web.xml"

    # Add security constraint to disable methods
    sed -i '/<\/web-app>/i \
    <!-- Security constraint to disable unnecessary HTTP methods -->\
    <security-constraint>\
        <web-resource-collection>\
            <web-resource-name>Disable HTTP Methods</web-resource-name>\
            <url-pattern>/*</url-pattern>\
            <http-method>PUT</http-method>\
            <http-method>DELETE</http-method>\
            <http-method>HEAD</http-method>\
            <http-method>OPTIONS</http-method>\
            <http-method>TRACE</http-method>\
        </web-resource-collection>\
        <auth-constraint />\
    </security-constraint>' "$web_xml"

    log_info "HTTP methods PUT, DELETE, HEAD, OPTIONS, TRACE disabled"
}

# Function: Remove default webapps
remove_default_webapps() {
    log_section "Removing default web applications"

    local webapps_dir="$TOMCAT_HOME/webapps"
    local apps_to_remove=("examples" "docs" "manager" "host-manager")

    for app in "${apps_to_remove[@]}"; do
        if [ -d "$webapps_dir/$app" ]; then
            log_info "Removing web application: $app"
            rm -rf "$webapps_dir/$app"
        fi

        if [ -f "$webapps_dir/${app}.war" ]; then
            log_info "Removing WAR file: ${app}.war"
            rm -f "$webapps_dir/${app}.war"
        fi
    done

    log_info "Default web applications removed"
}

# Function: Secure tomcat-users.xml
secure_tomcat_users() {
    log_section "Securing tomcat-users.xml"

    local tomcat_users="$TOMCAT_HOME/conf/tomcat-users.xml"

    log_info "Removing default users from tomcat-users.xml"

    # Create a minimal tomcat-users.xml
    cat > "$tomcat_users" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users xmlns="http://tomcat.apache.org/xml"
              xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
              xsi:schemaLocation="http://tomcat.apache.org/xml tomcat-users.xsd"
              version="1.0">
<!--
  NOTE: Default users have been removed for security purposes.
  Add users as needed with appropriate roles.
-->
</tomcat-users>
EOF

    # Set restrictive permissions
    chmod 600 "$tomcat_users"
    chown "$TOMCAT_USER:$TOMCAT_GROUP" "$tomcat_users"

    log_info "tomcat-users.xml secured"
}

# Function: Configure SELinux
configure_selinux() {
    log_section "Configuring SELinux contexts"

    # Check if SELinux is enabled
    if ! command -v getenforce >/dev/null 2>&1 || [ "$(getenforce)" = "Disabled" ]; then
        log_warn "SELinux is not enabled, skipping SELinux configuration"
        return 0
    fi

    log_info "Configuring SELinux contexts for Tomcat"

    # Install policycoreutils-python-utils if not present
    dnf install -y policycoreutils-python-utils >> "$LOG_FILE" 2>&1

    # Set SELinux contexts
    log_info "Setting bin_t context for Tomcat binaries"
    semanage fcontext -a -t bin_t "$TOMCAT_HOME/bin(/.*)?" 2>>"$LOG_FILE"
    restorecon -Rv "$TOMCAT_HOME/bin" >> "$LOG_FILE" 2>&1

    log_info "Setting lib_t context for Tomcat libraries"
    semanage fcontext -a -t lib_t "$TOMCAT_HOME/lib(/.*)?" 2>>"$LOG_FILE"
    restorecon -Rv "$TOMCAT_HOME/lib" >> "$LOG_FILE" 2>&1

    log_info "Setting etc_t context for Tomcat configuration"
    semanage fcontext -a -t etc_t "$TOMCAT_HOME/conf(/.*)?" 2>>"$LOG_FILE"
    restorecon -Rv "$TOMCAT_HOME/conf" >> "$LOG_FILE" 2>&1

    log_info "Setting var_t context for Tomcat data directories"
    semanage fcontext -a -t var_t "$TOMCAT_HOME/webapps(/.*)?" 2>>"$LOG_FILE"
    semanage fcontext -a -t var_t "$TOMCAT_HOME/work(/.*)?" 2>>"$LOG_FILE"
    semanage fcontext -a -t var_t "$TOMCAT_HOME/temp(/.*)?" 2>>"$LOG_FILE"
    semanage fcontext -a -t var_t "$TOMCAT_HOME/logs(/.*)?" 2>>"$LOG_FILE"
    restorecon -Rv "$TOMCAT_HOME/webapps" "$TOMCAT_HOME/work" "$TOMCAT_HOME/temp" "$TOMCAT_HOME/logs" >> "$LOG_FILE" 2>&1

    # Allow Tomcat to bind to network ports
    log_info "Configuring SELinux network permissions"
    setsebool -P httpd_can_network_connect 1 >> "$LOG_FILE" 2>&1

    log_info "SELinux contexts configured successfully"
}

# Function: Create systemd service
create_systemd_service() {
    log_section "Creating systemd service"

    local service_file="/etc/systemd/system/tomcat.service"

    log_info "Creating Tomcat systemd service file"

    cat > "$service_file" << EOF
[Unit]
Description=Apache Tomcat Web Application Container
After=network.target

[Service]
Type=forking

Environment=JAVA_HOME=$JAVA_HOME
Environment=CATALINA_PID=$TOMCAT_HOME/temp/tomcat.pid
Environment=CATALINA_HOME=$TOMCAT_HOME
Environment=CATALINA_BASE=$TOMCAT_HOME
Environment='CATALINA_OPTS=-Xms512M -Xmx1024M -server -XX:+UseParallelGC'
Environment='JAVA_OPTS=-Djava.awt.headless=true -Djava.security.egd=file:/dev/./urandom'

ExecStart=$TOMCAT_HOME/bin/startup.sh
ExecStop=$TOMCAT_HOME/bin/shutdown.sh

User=$TOMCAT_USER
Group=$TOMCAT_GROUP
UMask=0007
RestartSec=10
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable tomcat

    log_info "Tomcat systemd service created and enabled"
}

# Function: Generate installation report
generate_report() {
    log_section "Generating installation report"

    local report_file="/tmp/tomcat9_install_report_$(date +%Y%m%d_%H%M%S).txt"

    cat > "$report_file" << EOF
========================================
Tomcat 9 Security Installation Report
========================================
Installation Date: $(date)
Installation Path: $TOMCAT_HOME
Tomcat Version: $TOMCAT_VERSION
Java Version: $(java -version 2>&1 | head -n 1)
Java Home: $JAVA_HOME

========================================
Security Configurations Applied:
========================================
✓ Server header removed (set to empty string)
✓ Unified error pages configured (all errors redirect to error.html)
✓ Unnecessary HTTP methods disabled (PUT, DELETE, HEAD, OPTIONS, TRACE)
✓ Default web applications removed (examples, docs, manager, host-manager)
✓ tomcat-users.xml secured (default users removed, restrictive permissions)
✓ SELinux contexts configured (bin_t, lib_t, etc_t, var_t)
✓ Systemd service created and enabled

========================================
Service Management:
========================================
Start Tomcat:   systemctl start tomcat
Stop Tomcat:    systemctl stop tomcat
Restart Tomcat: systemctl restart tomcat
Status:         systemctl status tomcat
Logs:           journalctl -u tomcat -f

========================================
File Locations:
========================================
Tomcat Home:     $TOMCAT_HOME
Configuration:   $TOMCAT_HOME/conf/
Web Apps:        $TOMCAT_HOME/webapps/
Logs:            $TOMCAT_HOME/logs/
Service File:    /etc/systemd/system/tomcat.service
Install Log:     $LOG_FILE

========================================
Security Notes:
========================================
- Default Tomcat port is 8080
- All error codes are masked and redirect to error.html
- Management interfaces have been removed
- Server version information is hidden
- SELinux policies are applied for enhanced security

========================================
Next Steps:
========================================
1. Start the Tomcat service: systemctl start tomcat
2. Verify installation: curl http://localhost:8080
3. Deploy your applications to: $TOMCAT_HOME/webapps/
4. Configure firewall rules as needed
5. Set up SSL/TLS if required

EOF

    log_info "Installation report generated: $report_file"

    # Display summary
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Tomcat 9 Installation Completed!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "Installation Path: ${BLUE}$TOMCAT_HOME${NC}"
    echo -e "Version: ${BLUE}$TOMCAT_VERSION${NC}"
    echo -e "User: ${BLUE}$TOMCAT_USER${NC}"
    echo -e "Report: ${BLUE}$report_file${NC}"
    echo -e "Log File: ${BLUE}$LOG_FILE${NC}"
    echo ""
    echo -e "${YELLOW}To start Tomcat:${NC} systemctl start tomcat"
    echo -e "${YELLOW}To check status:${NC} systemctl status tomcat"
    echo ""
}

# Function: Display help
show_help() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Tomcat 9 Secure Installation Script for Rocky Linux

OPTIONS:
    --debug     Enable debug output
    --help      Show this help message

FEATURES:
    - Installs latest Tomcat 9 with Java 11 OpenJDK
    - Creates dedicated tomcat user and group
    - Applies security hardening configurations
    - Configures SELinux contexts
    - Creates systemd service
    - Generates detailed installation report

SECURITY HARDENING:
    - Server header removal
    - Unified error pages
    - HTTP method restrictions
    - Default webapp removal
    - Secure user configuration
    - SELinux integration

EOF
}

# Main function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --debug)
                DEBUG=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    log_info "Starting Tomcat 9 secure installation"
    log_info "Log file: $LOG_FILE"

    # Execute installation functions in order
    check_root
    install_java
    create_tomcat_user
    install_tomcat
    remove_server_header
    configure_error_pages
    remove_unnecessary_methods
    remove_default_webapps
    secure_tomcat_users
    configure_selinux
    create_systemd_service
    generate_report

    log_info "Tomcat 9 secure installation completed successfully!"
}

# Execute main function with all arguments
main "$@"
