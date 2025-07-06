#!/bin/bash

# Check if the system is Linux x86_64
if [ "$(uname -sm)" != 'Linux x86_64' ]; then
    echo "ERROR: Only Linux x86_64 is supported."
    exit 1
fi

# Check if the script is run as root
if [ "$(id -u)" != 0 ]; then
    echo "ERROR: Please run this script as root."
    exit 2
fi

# Ensure reboot command is available
if ! command -v reboot >/dev/null 2>&1; then
    export PATH=$PATH:/usr/sbin:/sbin
fi

# Determine package manager
if command -v apt-get >/dev/null 2>&1; then
    PKG_CMD=apt-get
elif command -v yum >/dev/null 2>&1; then
    PKG_CMD=yum
else
    PKG_CMD=no_pkg_cmd
    echo "WARNING: Only Redhat/CentOS and Debian/Ubuntu are tested."
fi

# Function to check and install a package
check_install_pkg() {
    if command -v "$1" >/dev/null 2>&1; then
        return 0
    fi
    if [ "$PKG_CMD" != "no_pkg_cmd" ]; then
        $PKG_CMD -y install "$2"
        if command -v "$1" >/dev/null 2>&1; then
            return 0
        fi
    fi
    echo "ERROR: $3 is not installed."
    exit $4
}

# Install required packages
check_install_pkg curl curl curl 3
check_install_pkg wget wget wget 4
check_install_pkg killall psmisc 'killall (psmisc package)' 5
check_install_pkg iptables iptables iptables 6

# Skip license check and ensure connectivity to GitHub
if ! curl -s --connect-timeout 5 https://github.com/ >/dev/null 2>&1; then
    echo "ERROR: Failed to connect to GitHub. Check your network."
    if [ "$PKG_CMD" != "no_pkg_cmd" ]; then
        $PKG_CMD -y upgrade ca-certificates
        if [ "$PKG_CMD" = "yum" ]; then
            $PKG_CMD -y upgrade nss nss-util nss-sysinit nss-tools
        fi
        if ! curl -s --connect-timeout 5 https://github.com/ >/dev/null 2>&1; then
            $PKG_CMD upgrade
            if ! curl -s --connect-timeout 5 https://github.com/ >/dev/null 2>&1; then
                echo "ERROR: Still unable to connect to GitHub."
                exit 7
            fi
        fi
    else
        exit 7
    fi
fi

# Set up working directory
mkdir -p /opt/655665.xyz
cd /opt/655665.xyz || exit 8

# Create startup script with default or provided environment variables
: "${THE655665XYZ_WIZARD_LISTENADDR:=0.0.0.0:8080}"
: "${THE655665XYZ_WIZARD_USERNAME:=admin}"
: "${THE655665XYZ_WIZARD_PASSWORD:=defaultpassword}"

echo "curl https://raw.githubusercontent.com/peopleassistant/655665xyz/main/launcher.sh | THE655665XYZ_WIZARD_LISTENADDR='$THE655665XYZ_WIZARD_LISTENADDR' THE655665XYZ_WIZARD_USERNAME='$THE655665XYZ_WIZARD_USERNAME' THE655665XYZ_WIZARD_PASSWORD='$THE655665XYZ_WIZARD_PASSWORD' bash" > startup.sh
chmod +x startup.sh

# Manage versioning
CURRENT_VERSION=0
if [ -e current_version ]; then
    CURRENT_VERSION=$(cat current_version)
fi
if [ -e "$CURRENT_VERSION/panel/database.json" ] && [ ! -e database/database.json ]; then
    mkdir -p database
    mv "$CURRENT_VERSION/panel/database.json" database/
    cd "$CURRENT_VERSION/panel" || exit 9
    ln -s ../../database/database.json .
    cd ../.. || exit 9
fi

LATEST_VERSION=v1.25
if [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
    mkdir -p "$LATEST_VERSION"
    cd "$LATEST_VERSION" || exit 9
    mkdir -p download/tmp
    cd download/tmp || exit 9
    rm -f wizard.tar.gz
    if ! wget -q https://github.com/peopleassistant/655665xyz/releases/download/$LATEST_VERSION/wizard.tar.gz; then
        echo "ERROR: Failed to download wizard.tar.gz from GitHub."
        exit 10
    fi
    mv wizard.tar.gz .. || exit 9
    cd ../.. || exit 9
    mkdir -p panel
    cd panel || exit 9
    tar zxvf ../download/wizard.tar.gz
    if [ -e ../../database/database.json ]; then
        ln -s ../../database/database.json .
    fi
    if [ -e wizard ]; then
        echo "$LATEST_VERSION" > ../../current_version
    else
        echo "ERROR: Failed to extract wizard executable."
        exit 11
    fi
    cd ../.. || exit 9
fi

# Stop existing processes
for proc in wizard geneva js301 js301tohttps real301 real301multi cmwallhttp cmwall; do
    killall "$proc" 2>/dev/null
done

# Clear iptables rules
iptables -F
iptables -X
iptables -P INPUT ACCEPT
iptables -P OUTPUT ACCEPT
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
iptables -t security -F
iptables -t security -X
iptables -t raw -F
iptables -t raw -X

# Navigate to panel directory
cd "$LATEST_VERSION/panel" || exit 9

# Create configuration file with defaults
cat > wizard.config.json << EOF
{
    "ListenAddr": "$THE655665XYZ_WIZARD_LISTENADDR",
    "Username": "$THE655665XYZ_WIZARD_USERNAME",
    "Password": "$THE655665XYZ_WIZARD_PASSWORD",
    "ProbeIPv4URL": "https://example.com",
    "ProbeIPv6URL": "https://example.com",
    "DatabasePath": "database.json",
    "ChainPrefix": "655665xyz"
}
EOF

# Set ulimit and start the wizard
ulimit -n 65535
nohup ./wizard wizard.config.json >wizard.log 2>&1 &
echo "======== Done. Panel is running on $THE655665XYZ_WIZARD_LISTENADDR ========"
