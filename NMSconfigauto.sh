#!/bin/bash
# Automated Configuration Script
# Author: Henry Picanco, 200529162@student.georgianc.on.ca
# Date: 2023-08-07
# Updated: 2023-08-15

# Function to print messages with timestamp
printOutput() {
    echo -e "\n[$(date +"%Y-%m-%d %H:%M:%S")] $1"
}

# Check if the script is being run with sudo/root
if [[ $(id -u) -ne 0 ]]; then
    printOutput "This script requires sudo: 'sudo bash [scriptName.sh]'."
    exit 1
fi

# Function to install the SSH
configureSSH() {
    printOutput "Checking pre-requisites for SSH configuration. . ."
    apt update -y
    apt install openssh-server -y
    apt install ssh -y
}

# Function to change hostname and set IP
configureHost() {
    local target="$1"
    local newHostname="$2"
    local newIP="$3"

    # SSH into the target system. --KeyCheck false so no inputs required  
    if ssh -o StrictHostKeyChecking= no "$target" << EOF
        echo "Configuring $newHostname" # Outputs for user, cannot use printOutput in this case since we are "in" a target
        
        # Update package information and redirect quietly
        sudo apt-get update > /dev/null


        # Check and change the hostname if needed
        if [[ \$(hostname) != "$newHostname" ]]; then
            echo "Changing hostname to $newHostname"
            echo "$newHostname" | sudo tee /etc/hostname
            sudo hostnamectl set-hostname "$newHostname" || { echo "Hostname change failed. Exiting."; exit 1; }
            echo "Hostname changed."
        else
            echo "Hostname was set correctly already."
        fi


        # Set new IP address
        echo "Changing IP to $newIP"
        sudo ip addr add "$newIP/24" dev eth0
        [ \$? -eq 0 ] && echo "IP was set."


        # Add hostname to /etc/hosts
        echo "Adding $newHostname to /etc/hosts"
        echo "192.168.16.4 $newHostname" | sudo tee -a /etc/hosts
        [ \$? -eq 0 ] && echo "Added $newHostname."


        # Install UFW if not installed
        echo "Installing UFW if not found"
        sudo apt-get install -y ufw > /dev/null


        # Enable UFW firewall and force the rules
        echo "Enabling UFW firewall"
        sudo ufw --force enable


        # Apply firewall rules
        echo "Applying firewall rules"
        sudo ufw allow 22/tcp


        # Restart rsyslog for logging and uncomment lines
        echo "Restarting rsyslog"
        sudo sed -i 's/#module(load="imudp")/module(load="imudp")/' /etc/rsyslog.conf
        sudo sed -i 's/#input(type="imudp" port="514")/input(type="imudp" port="514")/' /etc/rsyslog.conf
        sudo systemctl restart rsyslog
        [ \$? -ne 0 ] && { echo "Failed to restart rsyslog. Exiting."; exit 1; }


        # Check if rsyslog is running
        sudo systemctl is-active -q rsyslog && echo "Rsyslog is running on $newHostname" || { echo "Rsyslog is not running on $newHostname. Exiting."; exit 1; }

EOF
    then
        printOutput "$newHostname configuration complete, no errors."
    else
        printOutput "$newHostname configuration failed, exiting code 1."
        exit 1
    fi
}


# Main script starts here, our functions are being executed
configureSSH

# Target 1 configuration function, will call it then puts the vars in $ variables
configureHost "remoteadmin@172.16.1.10" "loghost" "192.168.16.3"

# Target 2 configuration same idea these will run one at a time though and takes time to run
configureHost "remoteadmin@172.16.1.11" "webhost" "192.168.16.4"

# NMS configuration
# Remove previous loghost and webhost entries from /etc/hosts
sed -i '/\(loghost\|webhost\)/d' /etc/hosts
# Add loghost entry to /etc/hosts
echo "192.168.16.3 loghost" | sudo tee -a /etc/hosts
# Add webhost entry to /etc/hosts
echo "192.168.16.4 webhost" | sudo tee -a /etc/hosts

# Install and check for curl
# Check if curl is already installed
if dpkg -s curl &> /dev/null; then
    printOutput "Curl is already installed."
else
    # Install curl if not already installed
    apt-get install -y curl > /dev/null || { printOutput "Curl install failed. Exiting."; exit 1; }
fi

#  Checking for the webhost page
if curl -s "http://webhost" | grep -q "Apache2 Default Page"; then
    printOutput "Found webhost page on http://webhost"
else
    printOutput "Failed to find webhost page on http://webhost. Was there a previous error?"
fi

# Display completion message where script ends
printOutput "Automated configuration process has been completed."

