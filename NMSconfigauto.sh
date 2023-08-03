#!/bin/bash

# Henry Picanco, 200529162@student.georgianc.on.ca

# Check if the script is being run with sudo/root
if [[ $(id -u) -ne 0 ]]; then # check user ID with id -u, if 0 its not in root privileges.
    echo "This script requires sudo: 'sudo bash [scriptName.sh]'."
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
    echo -e "\n[$(date +"%Y-%m-%d %H:%M:%S")] [ERROR] $1" # include ERROR indication w/ date & time
}

# Get the SSH
printOutput "Checking pre-requisites. . ."
sudo apt update -y 
sudo apt install openssh-server -y
sudo apt install ssh -y
# check for UFW only if necessary
printOutput "Checking if ufw is installed..."
# Check if ufw is installed, if not, install it
if ! checkForPackage "ufw"; then
    printOutput "ufw is not installed. Installing ufw..."
    sudo apt update -y
    sudo apt install ufw -y
fi

sudo ufw enable # turn firewall on (assuming fresh machine and containers)
sudo ufw allow ssh # allows ssh (default is port 22)
sudo ufw allow proto icmp

# target1-mgmt SHH, change the system name to loghost
sudo ssh remoteadmin@172.16.1.10 "sudo hostnamectl set-hostname loghost"
# Change the IP address to host number 3 on the LAN
lanIP="172.16.1.3"
interface=$(ip route | grep default | awk '{print $5}')
sudo ip addr add $lanIP/24 dev "$interface"

# Add webhost with host number 4 to the file
echo "172.16.1.4 webhost" | sudo tee -a /etc/hosts

# Allow connections to port 514/udp from the mgmt network (change 172.16.1.0/24 to your actual mgmt network)
sudo ufw allow from 172.16.1.10/24 to any port 514 proto udp
# Configure rsyslog to listen for UDP connections
printOutput "Configuring rsyslog to listen for UDP connections..."
sudo sed -i '/^#module(load="imudp")/s/^#//' /etc/rsyslog.conf # these modify the file directly
sudo sed -i '/^#input(type="imudp" port="514")/s/^#//' /etc/rsyslog.conf # ^#// removes the comments

# Restart rsyslog service
printOutput "Restarting rsyslog service..."
sudo systemctl restart rsyslog # force restarts it so the changes above will work

# target2-mgmt SSH, changing to webhost!
sudo ssh remoteadmin@172.16.1.11 "sudo hostnamectl set-hostname webhost"
# Change IP to host 4 on LAN
lanIP2="172.16.1.4" #target 2 host 4 on LAN
interface2=$(ip route | grep default | awk '{print $5}')
sudo ip addr add $lanIP2/24 dev "$interface2"

# Add loghost with host number 3 to the file
echo "172.16.1.3 loghost" | sudo tee -a /etc/hosts

# Allow connections to port 80/tcp from anywhere
sudo ufw allow 80/tcp
sudo ufw reload # all ufw rules allowed, this'll apply new rules

# Install Apache2 in its default configuration
if ! checkForPackage "apache2"; then
    printOutput "Apache2 is not installed. Installing Apache2..."
    sudo apt update -y
    sudo apt install apache2 -y

fi

# START the Apache2 in its default conf
if ! sudo systemctl is-active --quiet apache2; then # I was having issues with connecting to http://webhost
    printIfError "Apache2 isn't running! Starting up." # This outputs that it's being started
    sudo systemctl start apache2
fi

# Configure rsyslog on webhost to send logs to loghost
printOutput "Configuring rsyslog to send logs to loghost..."
sudo sed -i '$ a *.* @loghost' /etc/rsyslog.conf

# Restart rsyslog service
printOutput "Restarting rsyslog service..."
sudo systemctl restart rsyslog # force restarts it so the changes above will work

#  ssh key authentication for remoteadmin on loghost
# below should gen on the NMS if it doesn't exist
if [ ! -f ~/.ssh/id_rsa ]; then
    printOutput "SSH key on loghost generating..."
    ssh-keygen -t rsa -f ~/.ssh/id_rsa -N ""   # generate the key without a passphrase
fi


# copy public key to loghost 
printOutput "Authenticating SSH key for remoteadmin on loghost..."
ssh-copy-id remoteadmin@172.16.1.3




printOutput "Automated configuration has been applied."

