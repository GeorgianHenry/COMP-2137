#!/bin/bash

ip route
# show the interfaces
sudo inxi | grep "CPU:" | grep "speed:"
# get the speed and CPU model #
sudo dmidecode -t memory --no-sysfs --quiet
# this command is good but needs to be shortened.
sudo lshw -c disk -sanitize -quiet
#this command is REALLY good!
lspci -v
