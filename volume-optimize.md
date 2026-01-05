# AWS EBS Volume Resize Guide - Fix Elasticsearch Disk Full

## Problem Summary

**Error Message:**

```
index [.async-search] blocked by: [TOO_MANY_REQUESTS/12/disk usage exceeded flood-stage watermark, index has read-only-allow-delete block];
```

**Current Situation:**

- EC2 Instance: t3.medium
- Current Disk: 8 GB (92% used - 7.0G used, 648M available)
- Filesystem: ext4
- Device: /dev/nvme0n1p1 mounted on /
- Running: Elasticsearch in Docker
- Data Volume: 10-20M records/day

**Root Cause:**

- Disk usage exceeded 95% (flood-stage watermark)
- OpenSearch/Elasticsearch automatically set all indices to read-only mode
- 8GB disk is insufficient for Elasticsearch workload

---

## Solution: Resize EBS Volume

### Prerequisites

- AWS Console access
- SSH access to EC2 instance
- Sudo privileges

### Recommended New Size

- **Minimum:** 50 GB
- **Recommended:** 100 GB
- **Calculation:**
  - Daily data: 5-10 GB
  - 7-day retention: 35-70 GB
  - Working space (30%): 10-21 GB
  - OS + Docker: 5 GB
  - **Total:** 100 GB+

---

## Step-by-Step Instructions

### Step 1: Modify Volume in AWS Console

1. Go to **AWS Console** → **EC2** → **Volumes**
2. Select the volume attached to your instance (check Instance ID)
3. Click **Actions** → **Modify Volume**
4. Change **Size** from `8 GiB` → `50 GiB` (or more)
5. Click **Modify** → **Yes**
6. Wait until status shows "optimizing" (volume is usable during this state)

**Note:** This operation does NOT require stopping the instance or rebooting.

---

### Step 2: Extend Partition on EC2

```bash
# 1. Check current disk and partition layout
lsblk

# Expected output:
# NAME          MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
# nvme0n1       259:0    0   50G  0 disk
# ├─nvme0n1p1   259:1    0  7.9G  0 part /
# └─nvme0n1p15  259:2    0  105M  0 part /boot/efi

# 2. Check current disk usage
df -h /

# Current output:
# Filesystem      Size  Used Avail Use% Mounted on
# /dev/root       7.6G  7.0G  648M  92% /

# 3. Extend the partition (partition 1)
sudo growpart /dev/nvme0n1 1
```

**If you get error "growpart: command not found":**

```bash
sudo apt update
sudo apt install -y cloud-guest-utils
```

---

### Step 3: Extend Filesystem

```bash
# Resize the ext4 filesystem
sudo resize2fs /dev/nvme0n1p1

# Expected output:
# Filesystem at /dev/nvme0n1p1 is mounted on /; on-line resizing required
# old_desc_blocks = 1, new_desc_blocks = 7
# The filesystem on /dev/nvme0n1p1 is now 13106944 (4k) blocks long.
```

**If using XFS filesystem instead:**

```bash
sudo xfs_growfs /
```

---

### Step 4: Verify the Resize

```bash
# Check new disk size
df -h /

# Expected output after resize:
# Filesystem      Size  Used Avail Use% Mounted on
# /dev/root        49G  7.0G   42G  15% /

# Verify partition layout
lsblk

# Expected output:
# NAME          MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
# nvme0n1       259:0    0   50G  0 disk
# ├─nvme0n1p1   259:1    0 49.9G  0 part /
# └─nvme0n1p15  259:2    0  105M  0 part /boot/efi
```

---

## Post-Resize Actions

### 1. Unlock Elasticsearch Indices

After freeing up disk space, remove the read-only block:

```bash
# Unlock all indices
curl -X PUT "localhost:9200/*/_settings" -H 'Content-Type: application/json' -d'
{
  "index.blocks.read_only_allow_delete": null
}
'
```

### 2. Check Elasticsearch Status

```bash
# Check cluster health
curl -X GET "localhost:9200/_cluster/health?pretty"

# List all indices with sizes
curl -X GET "localhost:9200/_cat/indices?v&h=index,store.size&s=store.size:desc"

# Check disk allocation
curl -X GET "localhost:9200/_cat/allocation?v"
```

### 3. Delete Old Indices (if needed)

```bash
# List indices by date
curl "localhost:9200/_cat/indices?v"

# Delete old indices
curl -X DELETE "localhost:9200/your-old-index-2024-*"

# Force merge to reclaim space
curl -X POST "localhost:9200/_forcemerge?only_expunge_deletes=true"
```

---

## Prevention: Set Up Automated Cleanup

### Configure Index Lifecycle Management (ILM)

Create a policy to automatically delete old indices:

```bash
# Create ILM policy
curl -X PUT "localhost:9200/_ilm/policy/winlose-policy" -H 'Content-Type: application/json' -d'
{
  "policy": {
    "phases": {
      "hot": {
        "actions": {
          "rollover": {
            "max_primary_shard_size": "30GB",
            "max_age": "1d"
          }
        }
      },
      "delete": {
        "min_age": "7d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}
'

# Apply policy to index template
curl -X PUT "localhost:9200/_index_template/winlose-template" -H 'Content-Type: application/json' -d'
{
  "index_patterns": ["winlose-*"],
  "template": {
    "settings": {
      "index.lifecycle.name": "winlose-policy",
      "index.lifecycle.rollover_alias": "winlose"
    }
  }
}
'
```

### Set Up Disk Monitoring

Create a monitoring script:

```bash
# Create monitoring script
cat > /home/ubuntu/check_disk.sh << 'EOF'
#!/bin/bash
USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ $USAGE -gt 80 ]; then
    echo "WARNING: Disk usage is at ${USAGE}% on $(date)" | tee -a /var/log/disk_alert.log
    # Optional: Send notification
fi
EOF

# Make it executable
chmod +x /home/ubuntu/check_disk.sh

# Add to cron (check every 6 hours)
(crontab -l 2>/dev/null; echo "0 */6 * * * /home/ubuntu/check_disk.sh") | crontab -
```

### Configure CloudWatch Alarms

Set up CloudWatch alarms for:

- **Disk Space**: Alert when < 20% free
- **Elasticsearch Cluster Status**: Alert on yellow/red status

---

## Common Issues & Troubleshooting

### Issue 1: "growpart: command not found"

**Solution:**

```bash
sudo apt update
sudo apt install -y cloud-guest-utils
```

### Issue 2: "no space left on device" before resize

**Solution - Free up space temporarily:**

```bash
# Clean Docker
docker system prune -a

# Clean system logs
sudo journalctl --vacuum-size=100M

# Clean apt cache
sudo apt clean
```

### Issue 3: Partition not extending

**Solution:**

```bash
# Check if volume modification completed
aws ec2 describe-volumes-modifications --region your-region

# If stuck, try manual partition resize
sudo parted /dev/nvme0n1 resizepart 1 100%
sudo resize2fs /dev/nvme0n1p1
```

### Issue 4: Elasticsearch still showing read-only after unlock

**Solution:**

```bash
# Check watermark settings
curl -X GET "localhost:9200/_cluster/settings?include_defaults=true&pretty" | grep watermark

# Temporarily increase watermark (not recommended for production)
curl -X PUT "localhost:9200/_cluster/settings" -H 'Content-Type: application/json' -d'
{
  "transient": {
    "cluster.routing.allocation.disk.watermark.low": "90%",
    "cluster.routing.allocation.disk.watermark.high": "95%",
    "cluster.routing.allocation.disk.watermark.flood_stage": "97%"
  }
}
'
```

---

## Cost Estimation

### EBS GP3 Pricing (us-east-1)

| Size   | Monthly Cost |
| ------ | ------------ |
| 8 GB   | $0.64        |
| 50 GB  | $4.00        |
| 100 GB | $8.00        |
| 200 GB | $16.00       |

**Recommendation:** The cost increase is minimal compared to the operational issues caused by insufficient disk space.

---

## Summary of Commands

```bash
# Complete process in order:

# 1. Check current status
df -h /
lsblk

# 2. After modifying volume in AWS Console
sudo growpart /dev/nvme0n1 1
sudo resize2fs /dev/nvme0n1p1

# 3. Verify
df -h /
lsblk

# 4. Unlock Elasticsearch
curl -X PUT "localhost:9200/*/_settings" -H 'Content-Type: application/json' -d'{"index.blocks.read_only_allow_delete": null}'

# 5. Check Elasticsearch
curl "localhost:9200/_cluster/health?pretty"
curl "localhost:9200/_cat/indices?v"
```

---

## Timeline

- **Volume Modification**: 2-5 minutes
- **Partition Extension**: < 10 seconds
- **Filesystem Resize**: 10-30 seconds
- **Total Downtime**: **ZERO** (no reboot required)

---

## Notes

- ✅ No EC2 reboot required
- ✅ No data loss
- ✅ Can be done during production
- ✅ Elasticsearch continues running during resize
- ⚠️ Always backup important data before major changes
- ⚠️ Monitor disk usage regularly after resize

---

## Next Steps

1. Complete the volume resize
2. Set up ILM policy for automatic cleanup
3. Configure monitoring and alerts
4. Consider upgrading to 100GB for better headroom
5. Review retention policy (7 days may be too long for 10-20M records/day)
