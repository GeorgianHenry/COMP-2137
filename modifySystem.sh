#!/bin/bash

# Check if the script is being run with sudo/root
if [[ $(id -u) -ne 0 ]]; then
    echo "Sorry, but since this script changes system configuration, it must be run using sudo."
    exit 1
fi

# Function to output for users w/ a label
function printOutput() {
    echo -e "\n[$(date +"%Y-%m-%d %H:%M:%S")] $1"
}

# Function to display error messages
function printIfError() {
    echo -e "\n[$(date +"%Y-%m-%d %H:%M:%S")] [ERROR] $1"
}

# Function to check if a package is installed
function checkForPackage() {
    dpkg -s "$1" >/dev/null 2>&1
}

# Function to check if a service is running
function is_service_running() {
    systemctl is-active --quiet "$1"
}

# Function to update configuration file and check for success
function update_config_file() {
    local config_file="$1"
    local config_changes="$2"

    cp "$config_file" "$config_file.bak"
    sed -i "$config_changes" "$config_file"

    if [ $? -ne 0 ]; then
        printIfError "Failed to update $config_file."
        cp "$config_file.bak" "$config_file"  # Restore original file
        return 1
    fi
    
    return 0
}

# Update hostname
newHostname="autosrv"
currentHostname=$(hostname)
if [ "$currentHostname" != "$newHostname" ]; then
    printOutput "Changing hostname to $newHostname"
    hostnamectl set-hostname "$newHostname"
    if [ $? -ne 0 ]; then
        printIfError "Failed to change hostname."
        exit 1
    fi
fi

# Network Config

# Creates a backup
cp /etc/netplan/01-network-manager-all.yaml /etc/netplan/01-network-manager-all.yaml.bk_$(date +%Y%m%d%H%M)

# Define network configuration variables. Ensure you make a backup of code and server environment before changing this script!
staticip="192.168.16.21/24"
gatewayip="192.168.16.1"
nameserversip="[192.168.16.1]"

# Update network configuration
cat > /etc/netplan/01-network-manager-all.yaml <<EOF
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    ens33:
      dhcp4: false
      addresses:
        - $staticip
      routes:
        - to: 0.0.0.0/0
          via: $gatewayip
      nameservers:
        addresses: $nameserversip
    eth0:
      dhcp4: true
    ens34:
      dhcp4: true

EOF

# Install required software
printOutput "Installing required software"
if ! checkForPackage "openssh-server"; then
    apt-get install -y openssh-server
    if [ $? -ne 0 ]; then
        printIfError "Failed to install openssh-server."
        exit 1
    fi
fi

if ! checkForPackage "apache2"; then
    apt-get install -y apache2
    printOutput "Installing Apache2."
    if [ $? -ne 0 ]; then
        printIfError "Failed to install Apache2."
        exit 1
    fi
fi

if ! checkForPackage "squid"; then
    apt-get install -y squid
    if [ $? -ne 0 ]; then
        printIfError "Failed to install Squid."
        exit 1
    fi
fi

# Configure SSH server
ssh_config_file="/etc/ssh/sshd_config"
ssh_config_changes='s/#PasswordAuthentication.*/PasswordAuthentication no/; s/#PubkeyAuthentication.*/PubkeyAuthentication yes/'
update_config_file "$ssh_config_file" "$ssh_config_changes"
if [ $? -ne 0 ]; then
    printIfError "Failed to update SSH server configuration."
    exit 1
fi

# Configure Apache2
apache2_config_file="/etc/apache2/ports.conf"
apache2_config_changes='s/Listen 80/Listen 80\nListen 443/'
update_config_file "$apache2_config_file" "$apache2_config_changes"
if [ $? -ne 0 ]; then
    printIfError "Failed to update Apache2 configuration."
    exit 1
fi

# Configure Squid
squid_config_file="/etc/squid/squid.conf"
squid_config_changes='s/http_port 3128/http_port 3128 transparent/'
update_config_file "$squid_config_file" "$squid_config_changes"
if [ $? -ne 0 ]; then
    printIfError "Failed to update Squid configuration."
    exit 1
fi

# Configure firewall with UFW on ports!
printOutput "Configuring firewall with UFW"
ufw allow 22  # SSH
ufw allow 80  # HTTP
ufw allow 443  # HTTPS
ufw allow 3128  # Web Proxy
ufw --force enable

# Making user accounts!
printOutput "Creating user accounts. . ."
user_accounts=("dennis" "aubrey" "captain" "snibbles" "brownie" "scooter" "sandy" "perrier" "cindy" "tiger" "yoda")

for user in "${user_accounts[@]}"; do
    if ! id -u "$user" >/dev/null 2>&1; then
        useradd -m -s /bin/bash "$user"
        if [ $? -ne 0 ]; then
            printIfError "Failed to create user account: $user."
            exit 1
        fi
    fi

    # Generate SSH keys and add to authorized_keys
    ssh_dir="/home/$user/.ssh"
    authorized_keys_file="$ssh_dir/authorized_keys"

    if [ ! -d "$ssh_dir" ]; then
        mkdir "$ssh_dir"
        chmod 700 "$ssh_dir" #  700 removes all permissions for group, but keeps rwx for user
        chown "$user:$user" "$ssh_dir"
    fi

    if [ ! -f "$authorized_keys_file" ]; then
        touch "$authorized_keys_file"
        chmod 600 "$authorized_keys_file" # 600 owner has full read and write access to the file, while no other user can access the file
        chown "$user:$user" "$authorized_keys_file"
    fi

    ssh-keygen -t rsa -f "$ssh_dir/id_rsa" -N ""
    ssh-keygen -t ed25519 -f "$ssh_dir/id_ed25519" -N ""

    cat "$ssh_dir/id_rsa.pub" >> "$authorized_keys_file"
    cat "$ssh_dir/id_ed25519.pub" >> "$authorized_keys_file"

    chown "$user:$user" "$authorized_keys_file"
done

# Grant sudo access to dennis
printOutput "Granting sudo access to dennis"
if ! grep -q "^dennis" /etc/sudoers; then
    echo "dennis ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    if [ $? -ne 0 ]; then
        printIfError "Failed to grant sudo access to dennis."
        exit 1
    fi
fi


echo "Network configuration updated."
# Apply network config, another reason we needed sudo
printOutput "Applying network configuration"
sudo netplan apply


printOutput "System configuration completed successfully."

