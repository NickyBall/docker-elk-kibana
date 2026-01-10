# ELK Cluster Setup Guide

Multi-node Elasticsearch cluster with 2 nodes and 1 Kibana instance running on separate VMs using Docker Compose with volume mounts.

**Looking for a quick start?** See [QUICKSTART.md](QUICKSTART.md) for a simplified step-by-step guide.

## Architecture

- **VM1**: Elasticsearch Node 1 (Master-eligible + Data node)
- **VM2**: Elasticsearch Node 2 (Master-eligible + Data node)
- **VM3**: Kibana

## Prerequisites

### On All VMs

1. Docker and Docker Compose installed
2. Sufficient RAM (minimum 8GB recommended for Elasticsearch nodes)
3. Network connectivity between VMs (ports 9200 and 9300 open)

### VM-specific Requirements

**VM1 and VM2 (Elasticsearch nodes):**
- Port 9200 (HTTP API)
- Port 9300 (Transport - node communication)
- Mounted volume at `/mnt/elasticsearch-data`
- **CRITICAL: `vm.max_map_count` must be set to 262144** (see Step 4)

**VM3 (Kibana):**
- Port 5601 (Kibana web interface)

## Setup Instructions

### Step 1: Prepare Data Volumes (VM1 and VM2)

On both Elasticsearch VMs:

```bash
# Create mount point
sudo mkdir -p /mnt/elasticsearch-data

# Create logs directory
sudo mkdir -p /var/log/elasticsearch

# Set permissions (Elasticsearch Docker runs as UID 1000)
sudo chown -R 1000:1000 /mnt/elasticsearch-data
sudo chown -R 1000:1000 /var/log/elasticsearch

# Set proper permissions
sudo chmod -R 755 /mnt/elasticsearch-data
sudo chmod -R 755 /var/log/elasticsearch

# Verify
ls -ld /mnt/elasticsearch-data
```

### Step 2: Configure Network Settings

Get the IP addresses of your VMs:

```bash
# On each VM, get the IP address
ip addr show | grep inet
# or
hostname -I
```

**Example IPs (replace with your actual IPs):**
- VM1 (es-node1): `10.0.1.10`
- VM2 (es-node2): `10.0.1.11`
- VM3 (kibana): `10.0.1.12`

### Step 3: Configure Environment Variables

Create a `.env` file on each VM from the template:

```bash
cp .env.example .env
```

**On VM1**, edit `.env`:

```bash
nano .env
```

```bash
ES_NODE1_IP=10.0.1.10   # This VM's IP
ES_NODE2_IP=10.0.1.11   # VM2's IP
```

**On VM2**, edit `.env`:

```bash
nano .env
```

```bash
ES_NODE1_IP=10.0.1.10   # VM1's IP
ES_NODE2_IP=10.0.1.11   # This VM's IP
```

**On VM3**, edit `.env`:

```bash
nano .env
```

```bash
ES_NODE1_IP=10.0.1.10   # VM1's IP
ES_NODE2_IP=10.0.1.11   # VM2's IP
```

The docker-compose files will automatically read these environment variables.

### Step 4: Configure System Settings (VM1 and VM2) ⚠️ CRITICAL

**IMPORTANT**: This step is **required** or Elasticsearch will fail to start!

On both Elasticsearch VMs:

```bash
# REQUIRED: Increase virtual memory map limit
sudo sysctl -w vm.max_map_count=262144

# Make it permanent (survives reboot)
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf

# Verify the setting
sysctl vm.max_map_count

# Increase file descriptor limits
echo "* soft nofile 65536" | sudo tee -a /etc/security/limits.conf
echo "* hard nofile 65536" | sudo tee -a /etc/security/limits.conf
```

**Why is this required?**
- Elasticsearch uses a lot of memory-mapped files (mmapfs)
- The default Linux limit (65530) is too low
- Without this, you'll see error: "max virtual memory areas vm.max_map_count [65530] is too low"

**Alternative**: Run the automated setup script:

```bash
sudo bash setup-vm.sh
```

This script handles all system configuration automatically.

### Step 5: Start the Cluster

**On VM1 (Elasticsearch Node 1):**

```bash
cd /path/to/elk-cluster
docker-compose -f docker-compose-es-node1.yml up -d

# Check logs
docker-compose -f docker-compose-es-node1.yml logs -f
```

**On VM2 (Elasticsearch Node 2):**

```bash
cd /path/to/elk-cluster
docker-compose -f docker-compose-es-node2.yml up -d

# Check logs
docker-compose -f docker-compose-es-node2.yml logs -f
```

**Wait for both nodes to be up, then on VM3 (Kibana):**

```bash
cd /path/to/elk-cluster
docker-compose -f docker-compose-kibana.yml up -d

# Check logs
docker-compose -f docker-compose-kibana.yml logs -f
```

### Step 6: Verify Cluster

**Check cluster health:**

```bash
# From any Elasticsearch node or from a machine that can reach them
curl -X GET "http://VM1_IP:9200/_cluster/health?pretty"
```

Expected output:

```json
{
  "cluster_name" : "elk-cluster",
  "status" : "green",
  "number_of_nodes" : 2,
  "number_of_data_nodes" : 2,
  ...
}
```

**Check nodes:**

```bash
curl -X GET "http://VM1_IP:9200/_cat/nodes?v"
```

Expected output:

```
ip         heap.percent ram.percent cpu load_1m load_5m load_15m node.role master name
10.0.1.10            30          80   2    0.50    0.40     0.35 cdfhilmrstw *      es-node1
10.0.1.11            25          75   1    0.45    0.35     0.30 cdfhilmrstw -      es-node2
```

**Access Kibana:**

Open browser and go to: `http://VM3_IP:5601`

## Firewall Configuration

### VM1 and VM2 (Elasticsearch)

```bash
# Allow HTTP API (9200)
sudo ufw allow 9200/tcp

# Allow Transport (9300) - only from other cluster nodes
sudo ufw allow from VM2_IP to any port 9300 proto tcp  # On VM1
sudo ufw allow from VM1_IP to any port 9300 proto tcp  # On VM2

# Alternatively, if you trust the entire subnet:
sudo ufw allow from 10.0.1.0/24 to any port 9300 proto tcp
```

### VM3 (Kibana)

```bash
# Allow Kibana web interface
sudo ufw allow 5601/tcp
```

## Management Commands

### Start Services

```bash
# On Elasticsearch nodes
docker-compose -f docker-compose-es-nodeX.yml up -d

# On Kibana node
docker-compose -f docker-compose-kibana.yml up -d
```

### Stop Services

```bash
# On Elasticsearch nodes
docker-compose -f docker-compose-es-nodeX.yml down

# On Kibana node
docker-compose -f docker-compose-kibana.yml down
```

### View Logs

```bash
# Real-time logs
docker-compose -f docker-compose-es-nodeX.yml logs -f

# Last 100 lines
docker-compose -f docker-compose-es-nodeX.yml logs --tail=100
```

### Restart Services

```bash
docker-compose -f docker-compose-es-nodeX.yml restart
```

## Monitoring

### Cluster Health

```bash
# Overall health
curl "http://VM1_IP:9200/_cluster/health?pretty"

# Node stats
curl "http://VM1_IP:9200/_nodes/stats?pretty"

# Indices
curl "http://VM1_IP:9200/_cat/indices?v"

# Allocation
curl "http://VM1_IP:9200/_cat/allocation?v"
```

### Disk Usage

```bash
# Check disk space on Elasticsearch VMs
df -h /mnt/elasticsearch-data

# Check what's using space
du -sh /mnt/elasticsearch-data/*
```

### Container Stats

```bash
# Resource usage
docker stats elasticsearch-node1

# Container status
docker ps
```

## Troubleshooting

### Elasticsearch Won't Start - vm.max_map_count Error

**Error message:**
```
max virtual memory areas vm.max_map_count [65530] is too low, increase to at least [262144]
```

**Solution:**

On the Elasticsearch VM (host machine, not inside Docker):

```bash
# Set immediately
sudo sysctl -w vm.max_map_count=262144

# Make permanent
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf

# Verify
sysctl vm.max_map_count

# Restart Elasticsearch
docker-compose -f docker-compose-es-nodeX.yml restart
```

**Why this happens:**
- You skipped Step 4 of the setup
- This setting must be configured on the host OS, not in Docker
- Elasticsearch requires this for memory-mapped files

### Node Settings Error - Index Level Settings

**Error message:**
```
node settings must not contain any index level settings
```

**Solution:**

Remove index-level settings from docker-compose environment variables. Settings like `index.refresh_interval`, `index.number_of_replicas` cannot be set as node environment variables.

Set them via index templates after cluster is running (see Performance Tuning section).

### Nodes Won't Form Cluster

**Error message:**
```
completed handshake with [es-node1] at [10.0.x.x:9300]
but followup connection to [172.x.x.x:9300] failed
```

**This means:** Nodes are advertising Docker internal IPs instead of VM IPs.

**Solution:**

The docker-compose files now include `network.publish_host` which tells each node to advertise its VM's IP instead of the Docker internal IP.

Make sure your `.env` file has **both** IP addresses set correctly:

```bash
cat .env
```

Should show:
```
ES_NODE1_IP=10.0.167.119  # Your actual VM1 IP
ES_NODE2_IP=10.0.167.120  # Your actual VM2 IP
```

Then restart both nodes:

```bash
# On VM1
docker-compose -f docker-compose-es-node1.yml down
docker-compose -f docker-compose-es-node1.yml up -d

# On VM2
docker-compose -f docker-compose-es-node2.yml down
docker-compose -f docker-compose-es-node2.yml up -d
```

**Check network connectivity:**

```bash
# From VM1 to VM2
telnet VM2_IP 9300

# From VM2 to VM1
telnet VM1_IP 9300
```

**Check logs:**

```bash
docker-compose -f docker-compose-es-nodeX.yml logs --tail=200
```

**Common issues:**
- Firewall blocking port 9300
- Incorrect IP addresses in discovery.seed_hosts or .env file
- Different cluster.name on nodes
- vm.max_map_count not set
- Missing network.publish_host configuration (fixed in latest version)

### Permission Denied Errors

```bash
# Fix permissions on Elasticsearch VMs
sudo chown -R 1000:1000 /mnt/elasticsearch-data
sudo chmod -R 755 /mnt/elasticsearch-data
```

### Cluster Status Yellow or Red

```bash
# Check why
curl "http://VM1_IP:9200/_cluster/allocation/explain?pretty"

# Check shard status
curl "http://VM1_IP:9200/_cat/shards?v"
```

**Yellow status**: Usually means replicas aren't assigned. This is normal with only 2 nodes if you have many replicas.

**Red status**: Primary shards are missing. Check logs immediately.

### Out of Memory

```bash
# Check current memory settings in docker-compose file
# Adjust ES_JAVA_OPTS based on available RAM
# Rule of thumb: 50% of available RAM, max 32GB

# For 8GB RAM VM:
- "ES_JAVA_OPTS=-Xms4g -Xmx4g"

# For 16GB RAM VM:
- "ES_JAVA_OPTS=-Xms8g -Xmx8g"
```

### Kibana Can't Connect to Elasticsearch

```bash
# Check if Kibana can reach Elasticsearch
docker exec -it kibana curl http://VM1_IP:9200

# Check Kibana logs
docker-compose -f docker-compose-kibana.yml logs
```

## Data Backup

### Create Snapshot Repository

```bash
# Register snapshot repository
curl -X PUT "http://VM1_IP:9200/_snapshot/my_backup" -H 'Content-Type: application/json' -d'
{
  "type": "fs",
  "settings": {
    "location": "/usr/share/elasticsearch/data/backups"
  }
}
'

# Create snapshot
curl -X PUT "http://VM1_IP:9200/_snapshot/my_backup/snapshot_1?wait_for_completion=true"

# List snapshots
curl -X GET "http://VM1_IP:9200/_snapshot/my_backup/_all?pretty"
```

### Restore from Snapshot

```bash
# Restore snapshot
curl -X POST "http://VM1_IP:9200/_snapshot/my_backup/snapshot_1/_restore"
```

## Scaling

### Adding More Elasticsearch Nodes

1. Create a new `docker-compose-es-nodeX.yml` based on node1 or node2
2. Update node.name to be unique (e.g., es-node3)
3. Update discovery.seed_hosts to include all other nodes
4. Update cluster.initial_master_nodes (only needed for initial setup)
5. Start the new node

### Removing a Node

```bash
# Exclude node from allocation
curl -X PUT "http://VM1_IP:9200/_cluster/settings" -H 'Content-Type: application/json' -d'
{
  "transient": {
    "cluster.routing.allocation.exclude._name": "es-node2"
  }
}
'

# Wait for shards to relocate, then stop the node
docker-compose -f docker-compose-es-node2.yml down
```

## Performance Tuning

### Elasticsearch JVM Settings

Adjust based on your VM RAM:

```yaml
# For 8GB RAM
- "ES_JAVA_OPTS=-Xms4g -Xmx4g"

# For 16GB RAM
- "ES_JAVA_OPTS=-Xms8g -Xmx8g"

# For 32GB RAM
- "ES_JAVA_OPTS=-Xms16g -Xmx16g"
```

### Index Settings for High Volume

```bash
curl -X PUT "http://VM1_IP:9200/_template/default_template" -H 'Content-Type: application/json' -d'
{
  "index_patterns": ["*"],
  "settings": {
    "number_of_replicas": 1,
    "refresh_interval": "30s",
    "translog.durability": "async"
  }
}
'
```

## Security Notes

**IMPORTANT**: This setup has security disabled for simplicity. For production:

1. Enable X-Pack security
2. Configure TLS/SSL for transport and HTTP
3. Set up user authentication
4. Use firewall rules to restrict access
5. Consider using a VPN or private network

## Additional Resources

- [Elasticsearch Documentation](https://www.elastic.co/guide/en/elasticsearch/reference/current/index.html)
- [Kibana Documentation](https://www.elastic.co/guide/en/kibana/current/index.html)
- [Docker Compose Documentation](https://docs.docker.com/compose/)

---

## Quick Reference

| Component | Port | URL |
|-----------|------|-----|
| ES Node 1 | 9200, 9300 | http://VM1_IP:9200 |
| ES Node 2 | 9200, 9300 | http://VM2_IP:9200 |
| Kibana | 5601 | http://VM3_IP:5601 |

**Cluster Name**: `elk-cluster`
**Node Names**: `es-node1`, `es-node2`
**Data Volume**: `/mnt/elasticsearch-data`
**Logs Volume**: `/var/log/elasticsearch`
