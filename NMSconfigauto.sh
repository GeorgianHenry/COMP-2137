#!/bin/bash

# Henry Picanco, 200529162@student.georgianc.on.ca

# Check if the script is being run with sudo/root
if [[ $(id -u) -ne 0 ]]; then
    echo "This script requires sudo: 'sudo bash [scriptName.sh]'."
    exit 1
fi

# Check if a package is installed function
function checkForPackage() {
    dpkg -s "$1" >/dev/null 2>&1 # Ensure no output or error messages are displayed on the terminal
}

# Print messages function
function printOutput() {
    echo -e "\n[$(date +"%Y-%m-%d %H:%M:%S")] $1" # Print the timestamp and the first parameter with -e
}

# Print error messages function
function printIfError() {
    echo -e "\n[$(date +"%Y-%m-%d %H:%M:%S")] [ERROR] $1" # Include ERROR indication with date & time
}

# Get the SSH
printOutput "Checking pre-requisites. . ."
sudo apt update -y
sudo apt install openssh-server -y
sudo apt install ssh -y

# target1-mgmt SHH, change the system name to loghost, set up ufw

target1Management="remoteadmin@172.16.1.10"
if ssh -o StrictHostKeyChecking=no "$target1Management" << 'EOF'

   echo "Configuring Target 1 MGMT"
   echo "Adding packages/updating on target 1"

   apt-get update > /dev/null

   if [[ $(hostname) != "loghost" ]]; then

       echo "Renaming hostname to loghost"
       echo "loghost" > /etc/hostname
       hostnamectl set-hostname loghost

       # Check for status 0 after hostname change to display success or exit with error code 1
       if [ $? -eq 0 ]; then
           echo "Hostname changed."
       else
           echo "Hostname change failed. Exiting."
           exit 1
       fi

   else
       echo "Hostname was set correctly already. Did you run this script before?"
   fi

   # IP addressing on mgmt-1
   echo "Changing IP. . . host 3 on LAN"
   ip addr add 192.168.16.3/24 dev eth0

   if [ $? -eq 0 ]; then
       echo "IP was set on host 3"
   else
       echo "IP failed to set up correctly. Ending script."
       exit 1
   fi

   # Add webhost to /etc/hosts on the ssh
   echo "Adding webhost to /etc/hosts"
   echo "198.168.16.4 webhost" | sudo tee -a /etc/hosts

   if [ $? -eq 0 ]; then
       echo "Added the webhost."
   else
       echo "Failed to add webhost. Exiting script."
       exit 1
   fi

   # Checking if ufw is installed
   dpkg -s ufw &> /dev/null

   if [ $? -ne 0 ]; then
       echo "UFW not found."
       echo "Installing UFW."
       sudo apt-get install -y ufw > /dev/null

       if [ $? -eq 0 ]; then
           echo "Successfully installed UFW"
       else
           echo "UFW install failed. Exiting status 1."
           exit 1
       fi

   else
       echo "UFW is was found."
   fi

   # If statement checks the ufw status. Pipes the output with grep to search for the keyword "Status: active."
   # -w grep checks the full word
   # If "Status: active" appears in the ufw status output, then the following block is executed.

   if ufw status | grep -w -q "Status: active"; then
       echo "UFW firewall status active."
       echo "Firewall rules applying."

       # UFW rules can be added even if the firewall is active and already existing
       ufw allow proto udp from 172.16.1.0/24 to any port 514
       ufw allow 22/tcp

       echo "Restarting the firewall!"
       ufw reload

       # Check if the exit status of the ufw reload command was 0 (success) and display the appropriate message.
       if [ $? -eq 0 ]; then
           echo "Firewall restarted."
       else
           echo "Firewall failed restart. Ending script."
           exit 1
       fi

   else
       echo "Triggering firewall."

       # Turn on the firewall using ufw enable command
       ufw enable

       # Check if the exit status of the previous ufw enable command was 0 (success) and display the appropriate message.
       if [ $? -eq 0 ]; then
           echo "Firewall active."
       else
           echo "Firewall failed to enable and turn on. Stopping the script."
           exit 1
       fi

       echo "Firewall rules applying."
       ufw allow proto udp from 172.16.1.0/24 to any port 514
       ufw allow 22/tcp

       echo "Firewall restarting now."
       # Restart the firewall to apply the settings using the ufw reload command
       ufw reload

       # Check if the exit status of the ufw reload command was 0 (success) and display the appropriate message.
       if [ $? -eq 0 ]; then
           echo "Firewall reloaded."
       else
           echo "Firewall could restart properly. Ending script."
           exit 1
       fi

       echo "Firewall setup complete."
   fi

   # Rsyslog uncomments
   sed -i 's/#module(load="imudp")/module(load="imudp")/' /etc/rsyslog.conf

   if [ $? -eq 0 ]; then
       echo "Uncommented imudp lines."
   fi

   sed -i 's/#input(type="imudp" port="514")/input(type="imudp" port="514")/' /etc/rsyslog.conf

   if [ $? -eq 0 ]; then
       echo "Successfully uncommented lines to enable UDP listening on port 514"
   fi

   # Restart rsyslog
   echo "Rsyslog rebooting!"
   systemctl restart rsyslog

   if [ $? -eq 0 ]; then
       echo "Successfully restarted rsyslog"
   else
       echo "Could not restart rsyslog. Exiting script."
       exit 1
   fi

   if systemctl is-active -q rsyslog; then
       echo "Rsyslog is running on loghost"
   else
       echo "Rsyslog is not running on loghost. Ending script."
       exit 1
   fi

EOF

then

    echo "The previous configurations were successful. No exit codes were triggered."

else

    echo "Failed to apply configurations. Stopping script."
    exit 1

fi

# Target 2 CFG
target2Management="remoteadmin@172.16.1.11"

if ssh -o StrictHostKeyChecking=no "$target2Management" << 'EOF'

   echo "Configuring target 2 settings"
   echo "Adding packages/updating on target 2"

   apt-get update > /dev/null

   if ! dpkg -s apache2 &> /dev/null; then

       echo "apache2 not found.. installing."

       sudo apt-get install -y apache2 &> /dev/null

       if [ $? -eq 0 ]; then
           echo "Successfully installed Apache2"
           echo "Running apache2"
           sudo systemctl start apache2

           if systemctl is-active -q apache2; then
               echo "Started Apache2 successfully and is active"
           else
               echo "Apache2 failed to start"
               exit 1
           fi

           echo "Going to enable Apache2 for startups for future system boots"
           systemctl enable apache2

       else
           echo "Apache2 install failed. Exiting status 1."
           exit 1
       fi

   else
       echo "Apache2 was found."
   fi

   if [[ $(hostname) != "webhost" ]]; then

       echo "Switching hostname to webhost."
       echo "webhost" > /etc/hostname
       hostnamectl set-hostname webhost

       # If the exit status is 0, the hostname change was successful, then display it worked

       if [ $? -eq 0 ]; then
           echo "Hostname successfully changed."
       else
           echo "Failed to change hostname."
           exit 1
       fi

   else
       echo "Hostname was already set."
   fi

   # IP addressing on management 2
   echo "Changing . . . host 4 on the LAN"
   ip addr add 192.168.16.4/24 dev eth0

   if [ $? -eq 0 ]; then
       echo "IP set to host number 4"
   else
       echo "IP failed to set up. Exiting script"
       exit 1
   fi

   # Pushing the loghost to its /etc/hosts
   echo "Adding loghost to /etc/hosts"
   echo "192.168.16.3 loghost" | sudo tee -a /etc/hosts

   if [ $? -eq 0 ]; then
       echo "Loghost added successfully"
   else
       echo "Failed to add loghost."
       exit 1
   fi

   # Firewall setup
   dpkg -s ufw &> /dev/null

   if [ $? -ne 0 ]; then
       echo "UFW not installed (on MGMT-2)"
       sudo apt-get install -y ufw > /dev/null

       if [ $? -eq 0 ]; then
           echo "Successfully installed UFW"
       else
           echo "UFW install failed. Exiting status 1."
           exit 1
       fi

   else
       echo "UFW is was found."
   fi

   # This if statement checks the ufw status. If "Status: active" appears in the ufw status output, the if block runs.

   if ufw status | grep -w -q "Status: active"; then
       echo "UFW firewall status active."
       echo "Firewall rules applying."

       # Will add rules anyway, even if the firewall is active and already existing
       # Setting all the ports to allow in the firewall configuration.

       ufw allow 22/tcp
       ufw allow 80/tcp
       
       echo "Reloading firewall."

       # Restarting the firewall to apply the new changes using ufw reload.
       ufw reload

       # Check if the exit status of the ufw reload command was 0 (success) and display the appropriate message.
       if [ $? -eq 0 ]; then
           echo "Firewall restarted."
       else
           echo "Firewall failed restart Exiting script."
           exit 1
       fi

   else
       echo "Triggering firewall."

       # Turn on the firewall using ufw enable command
       ufw enable

       # Check if the exit status of the previous ufw enable command was 0 (success) and display the appropriate message.
       if [ $? -eq 0 ]; then
           echo "Firewall active."
       else
           echo "Firewall failed to enable and turn on. Stopping the script."
           exit 1
       fi

       echo "Adding TCP firewall."
       ufw allow 80/tcp
       ufw allow 22/tcp

       echo "Firewall restarting now."

       # Restart the firewall to apply settings using the ufw reload 
       ufw reload

       # Check ufw reload command was 0 and print success.
       if [ $? -eq 0 ]; then
           echo "Firewall restarted."
       else
           echo "Firewall failed to restart properly. Ending script."
           exit 1
       fi

       echo "Firewall enabled and setup."
   fi

   echo "*.* @loghost" | sudo tee -a /etc/rsyslog.conf

   if [ $? -eq 0 ]; then
       echo "*.* @loghost added to /etc/rsyslog.conf success"
   else
       echo "Failed to add *.* @loghost to /etc/rsyslog.conf"
   fi

EOF

then

    echo "Target2 configuration complete, no errors."

else

    echo "Target2 configuration failed, exiting code 1."
    exit 1

fi

echo "NMS CFG..."

sed -i '/\(loghost\|webhost\)/d' /etc/hosts

echo "192.168.16.3 loghost" | sudo tee -a /etc/hosts

if [ $? -eq 0 ]; then
    echo "Loghost added to /etc/hosts"
else
    echo "Loghost failed to add on /etc/hosts"
fi

echo "192.168.16.4 webhost" | sudo tee -a /etc/hosts

if [ $? -eq 0 ]; then
    echo "Webhost added to /etc/hosts"
else
    echo "Webhost failed to add on /etc/hosts"
fi

dpkg -s curl &> /dev/null

# When the exit status of the previous dpkg status command is not equal to 0, install the package if it's not installed on the system.

if [ $? -ne 0 ]; then
    "Getting curl for logs on http://webhost"

    # Installing curl using the -y option to automatically assume "yes" for all the installation prompts.
    apt-get install -y curl > /dev/null

    # If the exit status of the previous command is 0 (success), display a success message.
    if [ $? -eq 0 ]; then
        echo "Curl installed."
    # Using an else statement to handle an error. If the previous if statement checking exit status fails, then this else block will execute, displaying an error message and Exiting status 1. with exit code 1.
    else
        echo "Curl install failed. Did you lose connection?"
        exit 1
    fi
fi

if curl -s "http://webhost" | grep -q "Apache2 Default Page"; then
   echo "Found webhost page on http://webhost"
else
    echo "Failed to find webhost page on http://webhost"
fi

echo "Automated configuration has been applied."

