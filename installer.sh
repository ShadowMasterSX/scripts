#!/bin/bash

# Colors
RED='\033[1;31m'
GREEN='\033[1;32m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'
BOX='\033[1;44m'

# Spinner
spinner() {
    local pid=$!
    local delay=0.1
    local spinstr='|/-\'
    while ps a | awk '{print $1}' | grep -q "$pid"; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    wait $pid
    return $?
}

# Box with title
print_box() {
    echo -e "\n${BOX} $1 ${RESET}\n"
}

# Messages
print_info() {
    echo -e "${BLUE}➤ $1${RESET}"
}

print_success() {
    echo -e "${GREEN}[✔] $1${RESET}"
}

print_error() {
    echo -e "${RED}[✖] $1${RESET}"
}

progress_bar() {
    local i=0
    local total=20
    while [ $i -le $total ]; do
        sleep 0.05
        printf "["
        for ((j=0; j<=i; j++)); do printf "■"; done
        for ((j=i; j<total; j++)); do printf " "; done
        printf "] %d%%\r" $(( i * 100 / total ))
        ((i++))
    done
    echo ""
}

run_cmd() {
    eval "$1" &> /dev/null &
    spinner
    if [ $? -eq 0 ]; then
        print_success "$2"
    else
        print_error "$2"
    fi
}

# Check root
if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must be run as root"
    exit 1
fi

print_box "🛠 STARTING INSTALLATION"

progress_bar

# Step 1: Architecture and update
print_box "🏗 Adding i386 architecture and updating the system"
run_cmd "dpkg --add-architecture i386" "i386 architecture added"
run_cmd "apt update && apt -y upgrade" "System updated"

# Step 2: Main packages
print_box "📦 Installing main packages"
run_cmd "apt -y install make mc screen strace htop default-jdk mono-complete exim4 p7zip-full curl wget mariadb-server mariadb-client" "Main packages installed"

# Step 3: Dev dependencies
print_box "🔧 Installing development dependencies"
run_cmd "apt -y install build-essential gcc g++ make cmake libpcap-dev libjsoncpp-dev libpcre3" "Build-Tools installed"
run_cmd "apt -y install gcc-multilib g++-multilib libc6-dev" "Multilib-Unterstützung installed"
run_cmd "apt -y install libssl-dev libstdc++6" "Standardbibliotheken installed"
run_cmd "apt -y install libcurl4 libcurl4:i386 libcurl4-gnutls-dev" "libcurl installed"
run_cmd "apt -y install zlib1g-dev zlib1g-dev:i386" "zlib installed"
run_cmd "apt -y install libncurses5-dev libncurses5-dev:i386" "ncurses installed"
run_cmd "apt -y install pkg-config" "pkg-config installed"

# Step 6: DB libraries
print_box "📚 Installing DB libraries"
run_cmd "apt -y install libdb++-dev libdb-dev libdb5.3 libdb5.3++ libdb5.3++-dev libdb5.3-dbg libdb5.3-dev libmariadb-dev libmariadb-dev-compat" "DB libraries installed"

# Step 4: Build OpenSSL 1.1.1u
print_box "🔐 Building OpenSSL 1.1.1u"
run_cmd "cd /opt/"
run_cmd "wget https://www.openssl.org/source/openssl-1.1.1u.tar.gz"
run_cmd "tar xvf openssl-1.1.1u.tar.gz"
run_cmd "cd openssl-1.1.1u"
run_cmd "./config --prefix=/opt/openssl-1.1 --openssldir=/opt/openssl-1.1 shared"
run_cmd "make"
run_cmd "make install"
run_cmd "LD_LIBRARY_PATH=/opt/openssl-1.1/lib"
run_cmd "echo '/opt/openssl-1.1/lib' > /etc/ld.so.conf.d/openssl-1.1.conf"
run_cmd "ldconfig" "OpenSSL 1.1.1u installed and configured" "✅ Openssl 1.1 installed"

# Step 5: JSONCPP fix
JSONCPP_VERSION=$(ldconfig -p | grep libjsoncpp | grep -oP 'libjsoncpp\.so\.\K[0-9]+' | head -n1)
run_cmd "echo Detected libjsoncpp version: $JSONCPP_VERSION" "detect libjsoncpp" "✅ $JSONCPP_VERSION detect"
run_cmd "ln -sf /usr/lib/x86_64-linux-gnu/libjsoncpp.so.${JSONCPP_VERSION} /usr/lib/x86_64-linux-gnu/libjsoncpp.so.24" "Fix libjsoncpp.so.24 success"
run_cmd "run_cmd "ldconfig""

# Step 7: Other dependencies
print_box "➕ Additional dependencies"
run_cmd "apt -y install libmysqlcppconn-dev libjsoncpp-dev libmariadb-dev-compat curl libcurl4:i386 libcurl4-gnutls-dev" "✅ Additional dependencies installed"

# Step 8: Apache and PHP
print_box "🌐 Installing Apache and PHP"
run_cmd "apt -y install apache2 php libapache2-mod-php php-mysql php-curl php-gd php-mbstring php-xml php-xmlrpc php-soap php-intl php-zip" "✅ Apache and PHP installed"
run_cmd "systemctl restart apache2" "✅ Apache restarted"

# Step 9: Adminer
print_box "📁 Installing Adminer"
run_cmd "wget -O /var/www/html/adminer.php https://github.com/vrana/adminer/releases/download/v4.8.1/adminer-4.8.1.php" "✅ Adminer downloaded"
run_cmd "chown www-data:www-data /var/www/html/adminer.php" "✅ Permissions set"
run_cmd "chmod 755 /var/www/html/adminer.php" "✅ Permissions applied"

# Step 10: MySQL configuration
print_box "🛡 Checking MySQL configuration"

mysqladmin -u root status &> /dev/null
if [ $? -eq 0 ]; then
    print_info "MySQL root still has no password. Requesting password for configuration."
    read -p "Enter the password for the MySQL root user (empty = root): " MYSQL_ROOT_PASSWORD
    MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-root}
    run_cmd "mysql -e \"ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';\"" "Root password set"
else
    print_info "MySQL root already has a password configured. Skipping password setup."
    read -s -p "Enter the current root password to continue (only for Adminer configuration): " MYSQL_ROOT_PASSWORD
    echo ""
fi

run_cmd "mysql -u root -p${MYSQL_ROOT_PASSWORD} -e \"DELETE FROM mysql.user WHERE User='';\"" "Anonymous users removed"
run_cmd "mysql -u root -p${MYSQL_ROOT_PASSWORD} -e \"DROP DATABASE IF EXISTS test;\"" "Test database removed"
run_cmd "mysql -u root -p${MYSQL_ROOT_PASSWORD} -e \"FLUSH PRIVILEGES;\"" "Privileges flushed"

# Step 11: Adminer config (with caution!)
print_box "📝 Creating Adminer config"
cat > /var/www/html/adminer-config.php <<EOF
<?php
function adminer_object() {
    include_once "./plugins/plugin.php";
    class AdminerCustomization extends AdminerPlugin {
        function name() { return 'Adminer - MySQL Manager'; }
        function credentials() { return array('localhost', 'root', '${MYSQL_ROOT_PASSWORD}'); }
        function login(\$login, \$password) {
            return (\$login == 'root' && \$password == '${MYSQL_ROOT_PASSWORD}');
        }
    }
    return new AdminerCustomization();
}
EOF
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html
run_cmd "a2enmod rewrite && systemctl restart apache2" "Apache configured with rewrite"

# Final
print_box "✅ FINISHED"
SERVER_IP=$(hostname -I | awk '{print $1}')
echo -e "${CYAN}Access: http://${SERVER_IP}/adminer.php"
echo -e "User: root"
echo -e "Password: ${MYSQL_ROOT_PASSWORD}${RESET}"
echo -e "Thanks to fix Openssl instalation go to ッϑô︵Շɦ¡êท乡 "
