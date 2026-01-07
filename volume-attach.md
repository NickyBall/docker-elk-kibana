# AWS EBS Volume Mounting Guide

Complete guide for attaching, mounting, and configuring EBS volumes for both Docker and self-hosted Elasticsearch deployments.

---

## Table of Contents

1. [Create and Attach Volume](#1-create-and-attach-volume)
2. [Find the Device Name](#2-find-the-device-name)
3. [Format the Volume](#3-format-the-volume)
4. [Mount the Volume](#4-mount-the-volume)
5. [Configure Auto-Mount](#5-configure-auto-mount)
6. [Set Permissions](#6-set-permissions)
7. [Configure Elasticsearch](#7-configure-elasticsearch)
8. [Unmount Volume](#8-unmount-volume)

---

## 1. Create and Attach Volume

### Via AWS Console

1. Go to **EC2 Dashboard** → **Volumes**
2. Click **Create Volume**
3. Configure:
   - **Volume Type**: Throughput Optimized HDD (st1)
   - **Size**: Minimum 125 GB for st1
   - **Availability Zone**: Must match EC2 instance AZ
4. Click **Create Volume**
5. Select volume → **Actions** → **Attach Volume**
6. Select EC2 instance and device name `/dev/sdf`

### Via AWS CLI

```bash
# Create volume
aws ec2 create-volume \
    --volume-type st1 \
    --size 500 \
    --availability-zone us-east-1a \
    --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=elasticsearch-logs}]'

# Attach volume
aws ec2 attach-volume \
    --volume-id vol-xxxxxxxxx \
    --instance-id i-xxxxxxxxx \
    --device /dev/sdf
```

---

## 2. Find the Device Name

```bash
# List all block devices
lsblk

# Check NVMe devices (Nitro-based instances)
ls -l /dev/nvme*

# View recent kernel messages
dmesg | tail -20
```

**Common device names:**

- **Nitro instances**: `/dev/nvme1n1`, `/dev/nvme2n1`
- **Older instances**: `/dev/xvdf`, `/dev/xvdg`

**Example output:**

```
NAME         MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
nvme0n1      259:0    0   400G  0 disk
├─nvme0n1p1  259:1    0 399.9G  0 part /
nvme1n1      259:4    0   600G  0 disk     <- Your new volume
```

---

## 3. Format the Volume

**⚠️ Warning: This will erase all data on the volume!**

```bash
# Check if volume has filesystem
sudo file -s /dev/nvme1n1
# Output "data" = no filesystem

# Format with ext4
sudo mkfs -t ext4 /dev/nvme1n1

# Alternative: XFS (good for large files)
# sudo mkfs.xfs /dev/nvme1n1
```

---

## 4. Mount the Volume

```bash
# Create mount point
sudo mkdir -p /mnt/elasticsearch-data

# Mount the volume
sudo mount /dev/nvme1n1 /mnt/elasticsearch-data

# Verify mount
df -h | grep elasticsearch
lsblk
```

**Expected output:**

```
/dev/nvme1n1    589G   28K  559G   1% /mnt/elasticsearch-data
```

---

## 5. Configure Auto-Mount

```bash
# Get UUID of the volume
sudo blkid /dev/nvme1n1
# Output: UUID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# Backup fstab
sudo cp /etc/fstab /etc/fstab.backup

# Edit fstab
sudo nano /etc/fstab
```

**Add this line (replace with your UUID):**

```
UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  /mnt/elasticsearch-data  ext4  defaults,nofail  0  2
```

**Test the configuration:**

```bash
# Unmount and remount using fstab
sudo umount /mnt/elasticsearch-data
sudo mount -a

# Verify
df -h | grep elasticsearch
```

---

## 6. Set Permissions

### For Docker-based Elasticsearch

Elasticsearch Docker container runs as **UID 1000** by default.

```bash
# Set ownership to UID 1000
sudo chown -R 1000:1000 /mnt/elasticsearch-data

# Set permissions
sudo chmod -R 755 /mnt/elasticsearch-data

# Verify
ls -ld /mnt/elasticsearch-data
```

**Expected output:**

```
drwxr-xr-x 2 1000 1000 4096 Jan 07 10:30 /mnt/elasticsearch-data
```

### For Self-Hosted Elasticsearch

Elasticsearch typically runs as the `elasticsearch` user.

```bash
# Set ownership to elasticsearch user
sudo chown -R elasticsearch:elasticsearch /mnt/elasticsearch-data

# Set permissions
sudo chmod -R 755 /mnt/elasticsearch-data

# Verify
ls -ld /mnt/elasticsearch-data
```

**Expected output:**

```
drwxr-xr-x 2 elasticsearch elasticsearch 4096 Jan 07 10:30 /mnt/elasticsearch-data
```

**Optional: Create logs directory**

```bash
# For Docker
sudo mkdir -p /var/log/elasticsearch
sudo chown -R 1000:1000 /var/log/elasticsearch

# For Self-hosted
sudo mkdir -p /var/log/elasticsearch
sudo chown -R elasticsearch:elasticsearch /var/log/elasticsearch
```

---

## 7. Configure Elasticsearch

### For Docker (docker-compose.yml)

```yaml
version: "3.8"

services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.11.0
    container_name: elasticsearch
    environment:
      - node.name=es-logging
      - cluster.name=logging-cluster
      - discovery.type=single-node
      - bootstrap.memory_lock=true
      - "ES_JAVA_OPTS=-Xms4g -Xmx4g"
      - xpack.security.enabled=false
      # Optimizations for high-volume logging
      - indices.memory.index_buffer_size=30%
      - index.number_of_replicas=0
      - index.refresh_interval=30s
    ulimits:
      memlock:
        soft: -1
        hard: -1
      nofile:
        soft: 65536
        hard: 65536
    volumes:
      # Mount st1 volume for data
      - /mnt/elasticsearch-data:/usr/share/elasticsearch/data
      # Optional: separate logs location
      - /var/log/elasticsearch:/usr/share/elasticsearch/logs
    ports:
      - "9200:9200"
      - "9300:9300"
    networks:
      - elastic
    restart: unless-stopped
    healthcheck:
      test:
        ["CMD-SHELL", "curl -f http://localhost:9200/_cluster/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  elastic:
    driver: bridge
```

**Start Elasticsearch:**

```bash
docker-compose up -d
docker-compose logs -f elasticsearch
```

**Verify:**

```bash
curl -X GET "localhost:9200/_cluster/health?pretty"
docker exec -it elasticsearch ls -la /usr/share/elasticsearch/data
```

### For Self-Hosted Elasticsearch

**Edit configuration:**

```bash
sudo nano /etc/elasticsearch/elasticsearch.yml
```

**Update these lines:**

```yaml
# Path to directory where to store the data
path.data: /mnt/elasticsearch-data

# Path to log files
path.logs: /var/log/elasticsearch
```

**Migrate existing data (if any):**

```bash
# Stop Elasticsearch
sudo systemctl stop elasticsearch

# Copy existing data
sudo rsync -av /var/lib/elasticsearch/ /mnt/elasticsearch-data/

# Fix permissions
sudo chown -R elasticsearch:elasticsearch /mnt/elasticsearch-data

# Start Elasticsearch
sudo systemctl start elasticsearch

# Check status
sudo systemctl status elasticsearch
sudo tail -f /var/log/elasticsearch/elasticsearch.log
```

**Verify:**

```bash
curl -X GET "localhost:9200/_cluster/health?pretty"
curl -X GET "localhost:9200/_cat/nodes?v"
```

---

## 8. Unmount Volume

### Step 1: Stop Services

**For Docker:**

```bash
docker-compose down
docker ps  # Verify stopped
```

**For Self-hosted:**

```bash
sudo systemctl stop elasticsearch
sudo systemctl status elasticsearch
```

### Step 2: Check for Active Processes

```bash
# Check what's using the mount
sudo lsof +D /mnt/elasticsearch-data

# Alternative command
sudo fuser -m /mnt/elasticsearch-data

# Make sure you're not in that directory
pwd
cd ~
```

### Step 3: Unmount

```bash
# Unmount the volume
sudo umount /mnt/elasticsearch-data

# Verify unmounted
df -h | grep elasticsearch
mount | grep elasticsearch
lsblk
```

**If unmount fails (device is busy):**

```bash
# Kill processes using the mount
sudo fuser -km /mnt/elasticsearch-data

# Force unmount
sudo umount -f /mnt/elasticsearch-data

# Lazy unmount (unmounts when no longer busy)
sudo umount -l /mnt/elasticsearch-data
```

### Step 4: Remove from fstab

```bash
# Backup fstab
sudo cp /etc/fstab /etc/fstab.backup

# Edit fstab
sudo nano /etc/fstab
```

**Comment out or delete the line:**

```
# UUID=xxx  /mnt/elasticsearch-data  ext4  defaults,nofail  0  2
```

### Step 5: Detach from AWS

1. Go to **AWS Console** → **EC2** → **Volumes**
2. Select the volume
3. **Actions** → **Detach Volume**
4. Confirm detachment

---

## Quick Reference Commands

### Check Mount Status

```bash
# List all mounts
mount | grep elasticsearch

# Check disk usage
df -h /mnt/elasticsearch-data

# List block devices
lsblk

# Find mount point
findmnt /mnt/elasticsearch-data
```

### Monitor Performance

```bash
# Monitor disk I/O
iostat -x 1 nvme1n1

# Watch disk usage
watch -n 5 'df -h | grep elasticsearch'

# Check Elasticsearch stats (Docker)
docker-compose logs elasticsearch --tail=50

# Check Elasticsearch stats (Self-hosted)
sudo tail -f /var/log/elasticsearch/elasticsearch.log
```

### Verify Elasticsearch is Using Volume

```bash
# Check cluster health
curl -X GET "localhost:9200/_cluster/health?pretty"

# Check node stats
curl -X GET "localhost:9200/_nodes/stats/fs?pretty"

# Check indices
curl -X GET "localhost:9200/_cat/indices?v"

# Check disk allocation
curl -X GET "localhost:9200/_cat/allocation?v"
```

---

## Troubleshooting

### Permission Denied Errors

**For Docker:**

```bash
sudo chown -R 1000:1000 /mnt/elasticsearch-data
sudo chmod -R 755 /mnt/elasticsearch-data
```

**For Self-hosted:**

```bash
sudo chown -R elasticsearch:elasticsearch /mnt/elasticsearch-data
sudo chmod -R 755 /mnt/elasticsearch-data
```

### Mount Point Already Mounted

```bash
# Check what's mounted
mount | grep elasticsearch

# Unmount first
sudo umount /mnt/elasticsearch-data

# Then mount again
sudo mount /dev/nvme1n1 /mnt/elasticsearch-data
```

### Device Not Found

```bash
# Check available devices
lsblk

# Check if volume is attached in AWS Console
# EC2 → Volumes → Check "State" column
```

### Elasticsearch Won't Start

**Check logs:**

```bash
# Docker
docker-compose logs elasticsearch

# Self-hosted
sudo journalctl -u elasticsearch -f
sudo tail -f /var/log/elasticsearch/elasticsearch.log
```

**Common issues:**

- Incorrect permissions
- Not enough disk space
- Memory limits
- Port already in use

---

## Best Practices

1. **Always backup fstab** before editing
2. **Stop services** before unmounting
3. **Use UUID** in fstab instead of device names
4. **Test fstab** with `sudo mount -a` before rebooting
5. **Monitor disk usage** regularly for high-volume workloads
6. **Set up CloudWatch alarms** for disk space
7. **Use snapshots** for backups before major changes
8. **Document your volume IDs** and mount points

---

## Performance Tips for st1 Volumes

- **Baseline throughput**: 40 MB/s per TB
- **Burst throughput**: 250 MB/s per TB
- **Max throughput**: 500 MB/s per volume
- **Minimum size**: 125 GB
- **Best for**: Sequential I/O, log storage, big data

**Elasticsearch optimizations for st1:**

```yaml
# In docker-compose.yml or elasticsearch.yml
indices.memory.index_buffer_size: 30%
index.number_of_replicas: 0
index.refresh_interval: 30s
thread_pool.write.queue_size: 1000
```

---

## Migration Between Volumes

To move from one volume to another (e.g., nvme1n1 → nvme2n1):

```bash
# 1. Stop services
docker-compose down  # or sudo systemctl stop elasticsearch

# 2. Create temp mount for old volume
sudo mkdir -p /mnt/elasticsearch-old
sudo mount /dev/nvme1n1 /mnt/elasticsearch-old

# 3. Unmount and mount new volume
sudo umount /mnt/elasticsearch-data
sudo mount /dev/nvme2n1 /mnt/elasticsearch-data

# 4. Copy data
sudo rsync -av --progress /mnt/elasticsearch-old/ /mnt/elasticsearch-data/

# 5. Fix permissions (Docker: 1000:1000, Self-hosted: elasticsearch:elasticsearch)
sudo chown -R 1000:1000 /mnt/elasticsearch-data  # Docker
# OR
sudo chown -R elasticsearch:elasticsearch /mnt/elasticsearch-data  # Self-hosted

# 6. Update fstab with new UUID
sudo blkid /dev/nvme2n1
sudo nano /etc/fstab  # Replace old UUID with new one

# 7. Clean up and start
sudo umount /mnt/elasticsearch-old
docker-compose up -d  # or sudo systemctl start elasticsearch
```

---

## Summary

| Step            | Docker Command                                    | Self-Hosted Command                                                 |
| --------------- | ------------------------------------------------- | ------------------------------------------------------------------- |
| **Mount**       | `sudo mount /dev/nvme1n1 /mnt/elasticsearch-data` | Same                                                                |
| **Permissions** | `sudo chown -R 1000:1000 /mnt/elasticsearch-data` | `sudo chown -R elasticsearch:elasticsearch /mnt/elasticsearch-data` |
| **Configure**   | Edit `docker-compose.yml` volumes section         | Edit `/etc/elasticsearch/elasticsearch.yml`                         |
| **Start**       | `docker-compose up -d`                            | `sudo systemctl start elasticsearch`                                |
| **Stop**        | `docker-compose down`                             | `sudo systemctl stop elasticsearch`                                 |
| **Logs**        | `docker-compose logs -f`                          | `sudo tail -f /var/log/elasticsearch/elasticsearch.log`             |
| **Verify**      | `curl localhost:9200`                             | Same                                                                |

---

**Last Updated**: January 2025  
**Tested on**: Ubuntu 20.04/22.04 with Nitro-based EC2 instances
