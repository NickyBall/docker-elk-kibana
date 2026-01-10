#!/bin/bash

# ELK Cluster VM Setup Script
# Run this script on each Elasticsearch VM to prepare the system

set -e

echo "======================================"
echo "ELK Cluster VM Setup Script"
echo "======================================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script with sudo"
    exit 1
fi

echo "Step 1: Creating directories..."
mkdir -p /mnt/elasticsearch-data
mkdir -p /var/log/elasticsearch
echo "✓ Directories created"

echo ""
echo "Step 2: Setting permissions..."
chown -R 1000:1000 /mnt/elasticsearch-data
chown -R 1000:1000 /var/log/elasticsearch
chmod -R 755 /mnt/elasticsearch-data
chmod -R 755 /var/log/elasticsearch
echo "✓ Permissions set"

echo ""
echo "Step 3: Configuring system settings..."

# Set vm.max_map_count
sysctl -w vm.max_map_count=262144

# Make it permanent
if ! grep -q "vm.max_map_count=262144" /etc/sysctl.conf; then
    echo "vm.max_map_count=262144" >> /etc/sysctl.conf
fi

echo "✓ System settings configured"

echo ""
echo "Step 4: Setting file descriptor limits..."

# Set file descriptor limits
if ! grep -q "* soft nofile 65536" /etc/security/limits.conf; then
    echo "* soft nofile 65536" >> /etc/security/limits.conf
    echo "* hard nofile 65536" >> /etc/security/limits.conf
fi

echo "✓ File descriptor limits set"

echo ""
echo "======================================"
echo "Setup Complete!"
echo "======================================"
echo ""
echo "Next steps:"
echo "1. Copy the appropriate docker-compose file to this VM"
echo "2. Update IP addresses in the docker-compose file"
echo "3. Start the service with: docker-compose -f <file> up -d"
echo ""
echo "Verification commands:"
echo "  - Check directories: ls -la /mnt/elasticsearch-data"
echo "  - Check vm.max_map_count: sysctl vm.max_map_count"
echo "  - Check file limits: ulimit -n"
echo ""
