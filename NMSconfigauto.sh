#!/bin/bash

# Henry Picanco, 200529162@student.georgianc.on.ca

# Function to print messages with timestamp
printOutput() {
    echo -e "\n[$(date +"%Y-%m-%d %H:%M:%S")] $1"
}

# Check if the script is being run with sudo/root
if [[ $(id -u) -ne 0 ]]; then
    printOutput "This script requires sudo: 'sudo bash [scriptName.sh]'."
    exit 1
fi

# Function to configure SSH
configureSSH() {
    printOutput "Checking pre-requisites. . ."
    sudo apt update -y
    sudo apt install openssh-server -y
    sudo apt install ssh -y
}

# Function to change hostname and set IP
configureHost() {
    local target="$1"
    local newHostname="$2"
    local newIP="$3"

    if ssh -o StrictHostKeyChecking=no "$target" << EOF
        echo "Configuring $newHostname"
        
        sudo apt-get update > /dev/null

        if [[ \$(hostname) != "$newHostname" ]]; then
            echo "Changing hostname to $newHostname"
            echo "$newHostname" > /etc/hostname
            hostnamectl set-hostname "$newHostname" || { echo "Hostname change failed. Exiting."; exit 1; }
            echo "Hostname changed."
        else
            echo "Hostname was set correctly already."
        fi

        echo "Changing IP. . . $newIP"
        sudo ip addr add "$newIP/24" dev eth0
        [ \$? -eq 0 ] && echo "IP was set."

        echo "Adding $newHostname to /etc/hosts"
        echo "192.168.16.4 $newHostname" | sudo tee -a /etc/hosts
        [ \$? -eq 0 ] && echo "Added $newHostname."

        echo "Installing UFW if not found"
        sudo apt-get install -y ufw > /dev/null

        echo "Enabling UFW firewall"
        sudo ufw enable -y

        echo "Applying firewall rules"
        sudo ufw allow 22/tcp
        sudo ufw reload

        echo "Restarting rsyslog"
        sudo sed -i 's/#module(load="imudp")/module(load="imudp")/' /etc/rsyslog.conf
        sudo sed -i 's/#input(type="imudp" port="514")/input(type="imudp" port="514")/' /etc/rsyslog.conf
        sudo systemctl restart rsyslog
        [ \$? -ne 0 ] && { echo "Failed to restart rsyslog. Exiting."; exit 1; }

        sudo systemctl is-active -q rsyslog && echo "Rsyslog is running on $newHostname" || { echo "Rsyslog is not running on $newHostname. Exiting."; exit 1; }

EOF
    then
        printOutput "$newHostname configuration complete, no errors."
    else
        printOutput "$newHostname configuration failed, exiting code 1."
        exit 1
    fi
}

# Main script starts here
configureSSH

# Target 1 configuration function, will call it then puts the vars in $ variables
configureHost "remoteadmin@172.16.1.10" "loghost" "192.168.16.3"

# Target 2 configuration same idea these will run one at a time though and takes time to run
configureHost "remoteadmin@172.16.1.11" "webhost" "192.168.16.4"

# NMS configuration 
sudo sed -i '/\(loghost\|webhost\)/d' /etc/hosts
echo "192.168.16.3 loghost" | sudo tee -a /etc/hosts
echo "192.168.16.4 webhost" | sudo tee -a /etc/hosts

dpkg -s curl &> /dev/null || { sudo apt-get install -y curl > /dev/null || { printOutput "Curl install failed. Exiting."; exit 1; }; }

if curl -s "http://webhost" | grep -q "Apache2 Default Page"; then
   printOutput "Found webhost page on http://webhost"
else
    printOutput "Failed to find webhost page on http://webhost"
fi

printOutput "Automated configuration has been applied."

