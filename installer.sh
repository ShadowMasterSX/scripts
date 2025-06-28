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

# Spinner for background processes
spinner() {
    local pid=$!
    local delay=0.1
    local spinstr='|/-\'
    while ps -p $pid > /dev/null 2>&1; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    wait $pid
    return $?
}

# Print box with title
print_box() {
    echo -e "\n${BOX} $1 ${RESET}\n"
}

# Info, Success, Error messages
print_info() {
    echo -e "${BLUE}➤ $1${RESET}"
}
print_success() {
    echo -e "${GREEN}[✔] $1${RESET}"
}
print_error() {
    echo -e "${RED}[✖] $1${RESET}"
}

# Progress bar
progress_bar() {
    local i=0
    local total=20
    while [ $i -le $total ]; do
        sleep 0.03
        printf "["
        for ((j=0; j<=i; j++)); do printf "■"; done
        for ((j=i; j<total; j++)); do printf " "; done
        printf "] %d%%\r" $(( i * 100 / total ))
        ((i++))
    done
    echo ""
}

# Run commands with spinner and status
run_cmd() {
    eval "$1" &> /dev/null &
    spinner
    if [ $? -eq 0 ]; then
        print_success "$2"
    else
        print_error "$2"
    fi
}

# Check root permissions
if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must be run as root."
    exit 1
fi

print_box "🛠 STARTING INSTALLATION"

progress_bar

# Step 1: Architecture and update
print_box "🏗 Adding i386 architecture and updating the system"
run_cmd "dpkg --add-architecture i386" "i386 architecture added"
run_cmd "apt update && apt -y upgrade" "System updated and upgraded"

# Step 2: Main packages
print_box "📦 Installing main packages"
run_cmd "apt -y install make mc screen strace htop default-jdk mono-complete exim4 p7zip-full curl wget mariadb-server mariadb-client" "Main packages installed"

# Step 3: Dev dependencies
print_box "🔧 Installing development dependencies"
run_cmd "apt -y install build-essential gcc g++ make cmake libpcap-dev libjsoncpp-dev libpcre3" "Build tools installed"
run_cmd "apt -y install gcc-multilib g++-multilib libc6-dev" "Multilib support installed"
run_cmd "apt -y install libssl-dev libstdc++6" "Standard libraries installed"
run_cmd "apt -y install libcurl4 libcurl4:i386 libcurl4-gnutls-dev" "libcurl installed"
run_cmd "apt -y install zlib1g-dev zlib1g-dev:i386" "zlib installed"
run_cmd "apt -y install libncurses5-dev libncurses5-dev:i386" "ncurses installed"
run_cmd "apt -y install pkg-config" "pkg-config installed"

# Step 4: DB libraries
print_box "📚 Installing DB libraries"
run_cmd "apt -y install libdb++-dev libdb-dev libdb5.3 libdb5.3++ libdb5.3++-dev libdb5.3-dbg libdb5.3-dev libmariadb-dev libmariadb-dev-compat" "DB libraries installed"

# Step 5: Build OpenSSL 1.1.1u
print_box "🔐 Building OpenSSL 1.1.1u"
run_cmd "cd /opt && wget -q https://www.openssl.org/source/openssl-1.1.1u.tar.gz && tar xzf openssl-1.1.1u.tar.gz && cd openssl-1.1.1u && ./config --prefix=/opt/openssl-1.1 --openssldir=/opt/openssl-1.1 shared && make -s && make install" "OpenSSL 1.1.1u compiled and installed"
run_cmd "echo '/opt/openssl-1.1/lib' > /etc/ld.so.conf.d/openssl-1.1.conf && ldconfig" "OpenSSL 1.1.1u configured"

# Step 6: JSONCPP fix
print_box "🔧 Fixing libjsoncpp"
JSONCPP_VERSION=$(ldconfig -p | grep libjsoncpp | grep -oP 'libjsoncpp\.so\.\K[0-9]+' | head -n1)
if [ -n "$JSONCPP_VERSION" ]; then
    run_cmd "ln -sf /usr/lib/x86_64-linux-gnu/libjsoncpp.so.${JSONCPP_VERSION} /usr/lib/x86_64-linux-gnu/libjsoncpp.so.24" "libjsoncpp.so.24 symlinked"
    run_cmd "ldconfig" "ldconfig run"
else
    print_error "libjsoncpp not found, skipping symlink."
fi

# Step 7: Other dependencies
print_box "➕ Installing additional dependencies"
run_cmd "apt -y install libmysqlcppconn-dev libjsoncpp-dev libmariadb-dev-compat curl libcurl4:i386 libcurl4-gnutls-dev" "Additional dependencies installed"

# Step 8: Apache and PHP
print_box "🌐 Installing Apache and PHP"
run_cmd "apt -y install apache2 php libapache2-mod-php php-mysql php-curl php-gd php-mbstring php-xml php-xmlrpc php-soap php-intl php-zip" "Apache and PHP installed"
run_cmd "systemctl restart apache2" "Apache restarted"

# Step 9: PhpMyAdmin Installation
print_box "📁 Installing phpMyAdmin"
run_cmd "apt -y install phpmyadmin" "phpMyAdmin installed"
run_cmd "ln -sf /usr/share/phpmyadmin /var/www/html/phpmyadmin" "phpMyAdmin linked to /var/www/html/phpmyadmin"
run_cmd "chown -R www-data:www-data /usr/share/phpmyadmin" "phpMyAdmin permissions set"
run_cmd "systemctl reload apache2" "Apache reloaded for phpMyAdmin"

# Step 10: MySQL secure installation and user setup
print_box "🛡 Running mysql_secure_installation & Creating non-root user"

# Secure MySQL installation
print_info "Starting mysql_secure_installation (some prompts will require manual intervention)..."
mysql_secure_installation

# Create new MySQL user with full privileges (not root)
USER_CREATED=0
while [ $USER_CREATED -eq 0 ]; do
    read -p "Enter NEW MySQL username to create (not 'root'): " MYSQL_NEW_USER
    if [ "$MYSQL_NEW_USER" = "root" ] || [ -z "$MYSQL_NEW_USER" ]; then
        print_error "Username cannot be 'root' or empty. Please choose another username."
        continue
    fi
    read -s -p "Enter password for user '$MYSQL_NEW_USER': " MYSQL_NEW_PASSWORD
    echo ""
    read -s -p "Repeat password: " MYSQL_NEW_PASSWORD2
    echo ""
    if [ "$MYSQL_NEW_PASSWORD" != "$MYSQL_NEW_PASSWORD2" ]; then
        print_error "Passwords do not match!"
        continue
    fi

    SQL_CREATE_USER="CREATE USER '${MYSQL_NEW_USER}'@'localhost' IDENTIFIED BY '${MYSQL_NEW_PASSWORD}';"
    SQL_GRANT_PRIV="GRANT ALL PRIVILEGES ON *.* TO '${MYSQL_NEW_USER}'@'localhost' WITH GRANT OPTION;"
    SQL_FLUSH="FLUSH PRIVILEGES;"

    # Try to create user and grant privileges
    mysql -u root -p -e "${SQL_CREATE_USER} ${SQL_GRANT_PRIV} ${SQL_FLUSH}"
    if [ $? -eq 0 ]; then
        USER_CREATED=1
        print_success "MySQL user '$MYSQL_NEW_USER' created and given full access."
    else
        print_error "Failed to create user. Please check your MySQL root password and try again."
    fi
done

# Step 11: Info for phpMyAdmin
print_box "✅ INSTALLATION FINISHED"
SERVER_IP=$(hostname -I | awk '{print $1}')
echo -e "${CYAN}phpMyAdmin is now available at: http://${SERVER_IP}/phpmyadmin"
echo -e "Login with:"
echo -e "  Username: ${MYSQL_NEW_USER}"
echo -e "  Password: (the password you chose)${RESET}"
echo -e "Root login via phpMyAdmin is disabled/restricted for security."
