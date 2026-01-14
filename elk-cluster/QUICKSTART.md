# ELK Cluster Quick Start Guide

Simple step-by-step guide to get your 3-node Elasticsearch cluster with Kibana running across 4 VMs.

## Prerequisites

- 4 VMs with Docker and Docker Compose installed
- Network connectivity between VMs (ports 9200, 9300, 5601 open)
- Minimum 8GB RAM per Elasticsearch VM (VM1, VM2, VM3)

## Setup Steps

### Step 1: Get Your VM IP Addresses

On each VM, find the IP address:

```bash
hostname -I
# or
ip addr show | grep "inet " | grep -v 127.0.0.1
```

**Example:**
- VM1: `10.0.1.10` (Elasticsearch node1)
- VM2: `10.0.1.11` (Elasticsearch node2)
- VM3: `10.0.1.12` (Elasticsearch node3)
- VM4: `10.0.1.13` (Kibana)

---

### Step 2: Prepare Elasticsearch VMs (VM1, VM2, and VM3) ⚠️ CRITICAL

**IMPORTANT**: This step is **required** or Elasticsearch will fail to start!

On **all three Elasticsearch VMs (VM1, VM2, and VM3)**, you have two options:

**Option A - Automated (Recommended):**

```bash
# Run the setup script
sudo bash setup-vm.sh
```

**Option B - Manual:**

```bash
# Create directories
sudo mkdir -p /mnt/elasticsearch-data
sudo mkdir -p /var/log/elasticsearch

# Set permissions (UID 1000 for Docker Elasticsearch)
sudo chown -R 1000:1000 /mnt/elasticsearch-data
sudo chown -R 1000:1000 /var/log/elasticsearch

# CRITICAL: Set vm.max_map_count (required!)
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf

# Verify
sysctl vm.max_map_count
```

The setup script will:
- Create `/mnt/elasticsearch-data` and `/var/log/elasticsearch` directories
- Set proper permissions (UID 1000)
- **Configure vm.max_map_count=262144** (REQUIRED)
- Set file descriptor limits

---

### Step 3: Configure Environment Variables

On **each VM**, create a `.env` file from the template:

```bash
cp .env.example .env
nano .env
```

**VM1 - Edit .env:**
```bash
ES_NODE1_IP=10.0.1.10   # This VM's IP
ES_NODE2_IP=10.0.1.11   # VM2's IP
ES_NODE3_IP=10.0.1.12   # VM3's IP
```

**VM2 - Edit .env:**
```bash
ES_NODE1_IP=10.0.1.10   # VM1's IP
ES_NODE2_IP=10.0.1.11   # This VM's IP
ES_NODE3_IP=10.0.1.12   # VM3's IP
```

**VM3 - Edit .env:**
```bash
ES_NODE1_IP=10.0.1.10   # VM1's IP
ES_NODE2_IP=10.0.1.11   # VM2's IP
ES_NODE3_IP=10.0.1.12   # This VM's IP
```

**VM4 (Kibana) - Edit .env:**
```bash
ES_NODE1_IP=10.0.1.10   # VM1's IP
ES_NODE2_IP=10.0.1.11   # VM2's IP
ES_NODE3_IP=10.0.1.12   # VM3's IP
```

---

### Step 4: Start Services

**On VM1:**
```bash
docker-compose -f docker-compose-es-node1.yml up -d

# Check logs
docker-compose -f docker-compose-es-node1.yml logs -f
```

**On VM2:**
```bash
docker-compose -f docker-compose-es-node2.yml up -d

# Check logs
docker-compose -f docker-compose-es-node2.yml logs -f
```

**On VM3:**
```bash
docker-compose -f docker-compose-es-node3.yml up -d

# Check logs
docker-compose -f docker-compose-es-node3.yml logs -f
```

Wait for all three Elasticsearch nodes to be fully up (look for "Cluster health status changed from [YELLOW] to [GREEN]" or similar).

**On VM4 (Kibana):**
```bash
docker-compose -f docker-compose-kibana.yml up -d

# Check logs
docker-compose -f docker-compose-kibana.yml logs -f
```

---

### Step 5: Verify Cluster

**Check cluster health:**
```bash
curl http://10.0.1.10:9200/_cluster/health?pretty
```

**Expected output:**
```json
{
  "cluster_name" : "elk-cluster",
  "status" : "green",
  "number_of_nodes" : 3,
  "number_of_data_nodes" : 3
}
```

**Check nodes:**
```bash
curl http://10.0.1.10:9200/_cat/nodes?v
```

**Access Kibana:**
Open your browser to: `http://10.0.1.13:5601`

---

## Common Commands

### Start/Stop Services

```bash
# Start
docker-compose -f docker-compose-es-nodeX.yml up -d

# Stop
docker-compose -f docker-compose-es-nodeX.yml down

# Restart
docker-compose -f docker-compose-es-nodeX.yml restart

# View logs
docker-compose -f docker-compose-es-nodeX.yml logs -f
```

### Monitor Cluster

```bash
# Cluster health
curl http://10.0.1.10:9200/_cluster/health?pretty

# Node stats
curl http://10.0.1.10:9200/_cat/nodes?v

# Indices
curl http://10.0.1.10:9200/_cat/indices?v

# Disk usage
df -h /mnt/elasticsearch-data
```

---

## Troubleshooting

### Elasticsearch Won't Start - vm.max_map_count Error ⚠️

**Error:**
```
max virtual memory areas vm.max_map_count [65530] is too low, increase to at least [262144]
```

**Fix (on host machine):**

```bash
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
docker-compose -f docker-compose-es-nodeX.yml restart
```

This happens if you skipped Step 2. The setting must be on the **host OS**, not in Docker.

### Nodes Won't Form Cluster - Docker IP Issue

**Error:** `completed handshake but followup connection to [172.x.x.x:9300] failed`

**Fix:** Ensure `.env` has the correct **VM IPs** (not Docker IPs like 172.x.x.x):

```bash
cat .env
# Should show your actual VM IPs like:
# ES_NODE1_IP=10.0.167.119
# ES_NODE2_IP=10.0.167.120
```

Restart both nodes after fixing:
```bash
docker-compose -f docker-compose-es-nodeX.yml down
docker-compose -f docker-compose-es-nodeX.yml up -d
```

**Other checks:**

1. Check network connectivity:
   ```bash
   telnet 10.0.1.11 9300  # From VM1 to VM2
   ```

2. Check firewall rules:
   ```bash
   sudo ufw status
   # Make sure ports 9200 and 9300 are open
   ```

### Permission Errors

```bash
sudo chown -R 1000:1000 /mnt/elasticsearch-data
sudo chmod -R 755 /mnt/elasticsearch-data
```

### Check Logs for Errors

```bash
docker-compose -f docker-compose-es-node1.yml logs --tail=100
```

---

## File Structure

```
elk-cluster/
├── docker-compose-es-node1.yml   # For VM1 (Elasticsearch node1)
├── docker-compose-es-node2.yml   # For VM2 (Elasticsearch node2)
├── docker-compose-es-node3.yml   # For VM3 (Elasticsearch node3)
├── docker-compose-kibana.yml     # For VM4 (Kibana)
├── .env.example                   # Template
├── .env                           # Your actual config (create this)
├── setup-vm.sh                    # VM preparation script
└── README.md                      # Detailed documentation
```

---

## Next Steps

1. **Index some data**: Use Kibana Dev Tools or curl to index documents
2. **Create visualizations**: Use Kibana to visualize your data
3. **Set up monitoring**: Configure cluster monitoring in Kibana
4. **Configure backups**: Set up snapshot repositories

See [README.md](README.md) for detailed documentation on backups, scaling, performance tuning, and more.

---

## Quick Test

Send some data to Elasticsearch:

```bash
# Create an index with sample data
curl -X POST "http://10.0.1.10:9200/test-index/_doc" -H 'Content-Type: application/json' -d'
{
  "message": "Hello ELK Cluster!",
  "timestamp": "'$(date -Iseconds)'"
}
'

# Search the data
curl -X GET "http://10.0.1.10:9200/test-index/_search?pretty"
```

Then view it in Kibana at `http://10.0.1.13:5601`

---

That's it! Your ELK cluster is ready to use.
