#!/bin/bash
echo "System Status"
sudo inxi
lsmem --output-all
echo "Showing FREE SPACE"
df -h #-h means show it in human format

touch systemstatus.sh
