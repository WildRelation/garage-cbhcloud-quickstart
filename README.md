# Garage on cbhcloud

Deploy [Garage](https://garagehq.deuxfleurs.fr/) (S3-compatible object storage) on cbhcloud.

## Prerequisites

- Docker installed locally
- GitHub account with a Personal Access Token (`write:packages` scope)
- cbhcloud account

---

## 1. Create the Docker image

Create a new directory and add these three files:

**Dockerfile**
```dockerfile
FROM dxflrs/garage:v2.1.0 AS garage

FROM alpine:3.19
COPY --from=garage /garage /usr/local/bin/garage
COPY garage.toml /etc/garage.toml
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
EXPOSE 3900 3901 3902 3903
ENTRYPOINT ["/entrypoint.sh"]
CMD ["server"]
```

**garage.toml**
```toml
metadata_dir = "/data/meta"
data_dir = "/data/data"
db_engine = "sqlite"
replication_factor = 1

rpc_bind_addr = "[::]:3901"

[s3_api]
api_bind_addr = "[::]:3900"
s3_region = "garage"

[admin]
api_bind_addr = "[::]:3903"
```

**entrypoint.sh**
```sh
#!/bin/sh
set -e
mkdir -p /data/meta /data/data
exec garage "$@"
```

Build and push:
```bash
echo "YOUR_GITHUB_TOKEN" | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
docker build -t ghcr.io/YOUR_GITHUB_USERNAME/garage-cbhcloud:latest .
docker push ghcr.io/YOUR_GITHUB_USERNAME/garage-cbhcloud:latest
```

Make the package public:
- Go to `github.com/YOUR_GITHUB_USERNAME?tab=packages`
- Select `garage-cbhcloud` → Package settings → **Change visibility → Public**

---

## 2. Create the deployment

**Image tag:** `ghcr.io/YOUR_GITHUB_USERNAME/garage-cbhcloud:latest`  
**Image start arguments:** `server`  
**Visibility:** Public  
**Health check path:** `/`

**Environment variables:**

| Name | Value |
|---|---|
| `PORT` | `3900` |
| `GARAGE_RPC_SECRET` | output of `openssl rand -hex 32` |

**Persistent storage:**

| Name | App path |
|---|---|
| `garage-data` | `/data` |

---

## 3. Initialize Garage

SSH into the container:
```bash
ssh <deployment-name>@deploy.cloud.cbh.kth.se
```

Get the node ID:
```bash
garage node id
```

Assign layout (replace `<node-id>` with the full hex string):
```bash
garage layout assign -z dc1 -c 1G <node-id>
garage layout apply --version 1
```

Create a bucket and access key:
```bash
garage bucket create ducklake
garage key create ducklake-key
```

Save the **Key ID** (`GK...`) and **Secret key**.

Grant permissions:
```bash
garage bucket allow --read --write --owner ducklake --key ducklake-key
```

---

## 4. Connect with DuckDB

```python
con.execute("""
CREATE OR REPLACE SECRET garage_secret (
    TYPE s3,
    KEY_ID 'GKxxxxxxxxxxxx',
    SECRET 'your-secret-key',
    ENDPOINT '<deployment-name>.app.cloud.cbh.kth.se',
    REGION 'garage',
    URL_STYLE 'path',
    USE_SSL true
);
""")
```

> `REGION 'garage'` must match `s3_region` in `garage.toml`.
