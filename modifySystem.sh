#!/bin/bash

# Check if the script is being run with sudo/root
if [[ $(id -u) -ne 0 ]]; then # check user ID with id -u, if 0 its not in	 root privileges.
    echo "Sorry, but since this script changes system configuration, it must be run using sudo."
    exit 1
fi


# Check if a package is installed function
function checkForPackage() {
    dpkg -s "$1" >/dev/null 2>&1 #  2>&1 will ensure no output or error messages are displayed on terminal
}

# Print messages function
function printOutput() {
    echo -e "\n[$(date +"%Y-%m-%d %H:%M:%S")] $1" # prints the timestamp and the first parameter with -e
}

# Print error messages function
function printIfError() {
    echo -e "\n[$(date +"%Y-%m-%d %H:%M:%S")] [ERROR] $1" # same as above but includes ERROR indication
}

# Function to check if a service is running
function is_service_running() {
    systemctl is-active --quiet "$1"
}

# Update config file and check if succeeded
function update_config_file() {
    local config_file="$1"
    local config_changes="$2"

    cp "$config_file" "$config_file.bak"    # .bak is for backups, use copy command
    sed -i "$config_changes" "$config_file" # update the config file using sed
    
    if [ $? -ne 0 ]; then 
        printIfError "Failed to update $config_file."
        cp "$config_file.bak" "$config_file" # applies the .bak file
        return 1 # an error occurred during the execution of the function
    fi 
    
    return 0 # the function executed without any errors
}

# Update hostname
newHostname="autosrv" # add the new hostname here
currentHostname=$(hostname) # add the current hostname to a variable
if [ "$currentHostname" != "$newHostname" ]; then # if statement for redundancy, why change it if its already changed
    printOutput "Changing hostname to $newHostname" # print what is going here 
    hostnamectl set-hostname "$newHostname"
    if [ $? -ne 0 ]; then
        printIfError "Failed to change hostname."
        exit 1 # used to terminate script and give the exit status of 1 (an error) 
    fi
fi

# Network Config

# Creates a date and backup
cp /etc/netplan/01-network-manager-all.yaml /etc/netplan/01-network-manager-all.yaml.bk_$(date +%Y%m%d%H%M)

# Define network configuration variables. Ensure you make a backup of code and server environment before changing this script!
staticip="192.168.16.21/24"
gatewayip="192.168.16.1"
nameserversip="[192.168.16.1]"

# Update network configuration . . . logic is to access the .yaml, rewrite it, then apply later.
# netplan is case sensitive spaces matter. thus, the variables above offer easy configuration. 
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
# one oversight, what if the interface names aren't ens33, ens34, eth0, they will remain default then.
# Install required software
printOutput "Installing required software"
if ! checkForPackage "openssh-server"; then # Will check if the openssh is already installed
    apt-get install -y openssh-server >/dev/null # Installs openssh server, puts useless output to null
    if [ $? -ne 0 ]; then
        printIfError "Failed to install openssh-server. Likely a network issue has been detected, try restarting and check connectivity."
        exit 1
    fi
fi

if ! checkForPackage "apache2"; then
    apt-get install -y apache2 >/dev/null # Required software, same idea as before.
    printOutput "Installing Apache2."
    if [ $? -ne 0 ]; then # checks the exit status of the apt-get install command, if anything goes wrong it will take this condition
        printIfError "Failed to install Apache2. Reapply the configuration if you lost connection suddenly." # the prints error
        exit 1
    fi
fi

if ! checkForPackage "squid"; then
    apt-get install -y squid >/dev/null
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

    if [ -d "$ssh_dir" ]; then
        rm -rf "$ssh_dir" # Remove the existing .ssh directory
    fi

    mkdir "$ssh_dir"
    chmod 700 "$ssh_dir"
    chown "$user:$user" "$ssh_dir"

    touch "$authorized_keys_file"
    chmod 600 "$authorized_keys_file"
    chown "$user:$user" "$authorized_keys_file"

    ssh-keygen -t rsa -f "$ssh_dir/id_rsa" -N "" >/dev/null
    ssh-keygen -t ed25519 -f "$ssh_dir/id_ed25519" -N "" >/dev/null

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

