# Nginx Reverse Proxy for Private Elasticsearch

Setup nginx on the public server (Kibana VM3) to proxy requests to private Elasticsearch nodes.

## Quick Setup

### Step 1: Install Nginx on Public Server (VM3)

```bash
sudo apt update
sudo apt install nginx -y
sudo systemctl enable nginx
sudo systemctl start nginx
```

### Step 2: Configure Nginx

**Edit the config file:**

```bash
sudo nano /etc/nginx/sites-available/elasticsearch
```

**Paste this configuration:**

```nginx
upstream elasticsearch_cluster {
    server 10.0.1.10:9200 max_fails=3 fail_timeout=30s;  # Replace with ES Node1 private IP
    server 10.0.1.11:9200 max_fails=3 fail_timeout=30s;  # Replace with ES Node2 private IP
    keepalive 32;
}

server {
    listen 9200;
    server_name _;

    access_log /var/log/nginx/elasticsearch-access.log;
    error_log /var/log/nginx/elasticsearch-error.log;

    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
    client_max_body_size 100M;

    location / {
        proxy_pass http://elasticsearch_cluster;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_http_version 1.1;
        proxy_set_header Connection "";

        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;

        proxy_next_upstream error timeout http_502 http_503 http_504;
    }
}
```

**Replace the IPs:**
- Change `10.0.1.10` to your actual ES Node1 private IP
- Change `10.0.1.11` to your actual ES Node2 private IP

### Step 3: Enable the Configuration

```bash
# Create symlink
sudo ln -s /etc/nginx/sites-available/elasticsearch /etc/nginx/sites-enabled/

# Test configuration
sudo nginx -t

# If test passes, reload nginx
sudo systemctl reload nginx
```

### Step 4: Open Firewall Port

```bash
# Allow port 9200 from your laptop IP or network
sudo ufw allow from YOUR_LAPTOP_IP to any port 9200 proto tcp

# Or allow from anywhere (less secure)
sudo ufw allow 9200/tcp
```

### Step 5: Test from Your Laptop

```bash
# Test connection (replace PUBLIC_SERVER_IP with actual IP)
curl http://PUBLIC_SERVER_IP:9200

# Expected output:
{
  "name" : "es-node1" or "es-node2",
  "cluster_name" : "elk-cluster",
  ...
}

# Check cluster health
curl http://PUBLIC_SERVER_IP:9200/_cluster/health?pretty

# Send test log
curl -X POST "http://PUBLIC_SERVER_IP:9200/test-logs/_doc" \
  -H 'Content-Type: application/json' \
  -d '{
    "message": "Test from my laptop",
    "timestamp": "2025-01-08T12:00:00Z"
  }'
```

## Configuration Options

### Option 1: Simple Proxy (No Authentication)

Use `nginx-elasticsearch-proxy.conf` - good for development/testing

**Ports:**
- `9200` - Proxy to ES Node1 only
- `9201` - Proxy to ES Node2 only
- `9202` - Load-balanced between both nodes (recommended)

### Option 2: Secure Proxy (With Authentication)

Use `nginx-elasticsearch-secure.conf` - **recommended for production**

**Setup authentication:**

```bash
# Install apache2-utils
sudo apt install apache2-utils -y

# Create password file
sudo htpasswd -c /etc/nginx/.htpasswd myusername

# Enter password when prompted
```

**Use with authentication from laptop:**

```bash
# With curl
curl -u myusername:mypassword http://PUBLIC_SERVER_IP:9200

# In application code (Python)
from elasticsearch import Elasticsearch
es = Elasticsearch(
    ['http://PUBLIC_SERVER_IP:9200'],
    http_auth=('myusername', 'mypassword')
)
```

## Application Configuration

### Python (Elasticsearch library)

```python
from elasticsearch import Elasticsearch

es = Elasticsearch(['http://PUBLIC_SERVER_IP:9200'])

# Index a document
es.index(index='my-app-logs', document={
    'message': 'Application started',
    'level': 'INFO',
    'timestamp': '2025-01-08T12:00:00Z'
})
```

### Node.js (Elasticsearch client)

```javascript
const { Client } = require('@elastic/elasticsearch');

const client = new Client({
  node: 'http://PUBLIC_SERVER_IP:9200'
});

// Index a document
await client.index({
  index: 'my-app-logs',
  document: {
    message: 'Application started',
    level: 'INFO',
    timestamp: new Date()
  }
});
```

### Logstash

```conf
output {
  elasticsearch {
    hosts => ["http://PUBLIC_SERVER_IP:9200"]
    index => "logstash-%{+YYYY.MM.dd}"
  }
}
```

### Filebeat

```yaml
output.elasticsearch:
  hosts: ["http://PUBLIC_SERVER_IP:9200"]
  index: "filebeat-%{+yyyy.MM.dd}"
```

## Monitoring Nginx

### Check Status

```bash
sudo systemctl status nginx
```

### View Logs

```bash
# Access logs
sudo tail -f /var/log/nginx/elasticsearch-access.log

# Error logs
sudo tail -f /var/log/nginx/elasticsearch-error.log

# All nginx logs
sudo journalctl -u nginx -f
```

### Test Configuration

```bash
# Test config syntax
sudo nginx -t

# Reload without downtime
sudo systemctl reload nginx

# Restart (brief downtime)
sudo systemctl restart nginx
```

## Troubleshooting

### Nginx can't connect to private Elasticsearch

**Check from public server:**

```bash
# Can nginx reach the private ES nodes?
curl http://PRIVATE_ES_NODE1_IP:9200
telnet PRIVATE_ES_NODE1_IP 9200
```

**If not reachable:**
- Check network routing between VMs
- Check firewall rules on private ES nodes
- Ensure ES nodes are listening on `0.0.0.0` not `127.0.0.1`

### 502 Bad Gateway

```bash
# Check if Elasticsearch is running
curl http://PRIVATE_ES_NODE1_IP:9200

# Check nginx error logs
sudo tail -f /var/log/nginx/elasticsearch-error.log
```

### Connection timeout

```bash
# Increase timeouts in nginx config
proxy_connect_timeout 120s;
proxy_send_timeout 120s;
proxy_read_timeout 120s;
```

## Performance Tuning

### For High Volume Logging

```nginx
# In nginx config
worker_processes auto;
worker_connections 4096;

# In http block
keepalive_timeout 65;
keepalive_requests 1000;

# In upstream block
keepalive 64;  # Increase from 32
```

### Enable Compression

```nginx
# In location block
gzip on;
gzip_types application/json;
gzip_min_length 1000;
```

## Security Best Practices

1. **Use authentication** (htpasswd or OAuth)
2. **Whitelist IPs** - only allow your laptop/office IPs
3. **Use HTTPS** with SSL/TLS certificates
4. **Rate limiting** to prevent abuse
5. **Monitor access logs** for suspicious activity

## Advantages Over SSH Tunnel

✓ No need to keep SSH connection open from laptop
✓ Better for multiple developers/applications
✓ Can add authentication, rate limiting, caching
✓ Better logging and monitoring
✓ More production-ready
✓ Can load balance between ES nodes

---

**Next Step:** Update Kibana to also use the load-balanced endpoint at `http://localhost:9202`
