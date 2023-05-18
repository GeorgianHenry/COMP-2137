#!/bin/bash

echo "Loading System Update"
sudo apt update -y
sudo apt upgrade -y
touch systemupdate.sh
echo "System Update Complete"
