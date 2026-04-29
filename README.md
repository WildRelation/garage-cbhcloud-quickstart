# garage-cbhcloud-quickstart

Driftsätt [Garage](https://garagehq.deuxfleurs.fr/) (S3-kompatibel objektlagring) på cbhcloud med stöd för Admin API via nginx reverse proxy.

## Bakgrund och portproblem

cbhcloud exponerar bara den port som anges i `PORT`-miljövariabeln i Kubernetes Service. Övriga portar är blockerade av NetworkPolicy och kan inte nås från andra deployments.

Garage kräver två portar:
- **3900** – S3 API (publikt åtkomlig via `PORT=3900`)
- **3903** – Admin API (behövs internt av Access Manager)

**Lösning:** nginx lyssnar på port 3900 och fungerar som reverse proxy:
- `/v2/*` → port 3903 (Garage Admin API)
- allt annat → port 3905 (Garage S3 API, flyttad från 3900)

---

## Förutsättningar

- Docker installerat lokalt
- GitHub-konto med Personal Access Token (`write:packages`-behörighet)
- cbhcloud-konto

---

## 1. Bygg och pusha Docker-imagen

```bash
git clone https://github.com/WildRelation/garage-cbhcloud-quickstart.git
cd garage-cbhcloud-quickstart

echo "DITT_GITHUB_TOKEN" | docker login ghcr.io -u DITT_GITHUB_ANVÄNDARNAMN --password-stdin
docker build -t ghcr.io/DITT_GITHUB_ANVÄNDARNAMN/garage-cbhcloud-quickstart:latest .
docker push ghcr.io/DITT_GITHUB_ANVÄNDARNAMN/garage-cbhcloud-quickstart:latest
```

Gör paketet publikt:
- Gå till `github.com/DITT_GITHUB_ANVÄNDARNAMN?tab=packages`
- Välj `garage-cbhcloud-quickstart` → Package settings → **Change visibility → Public**

---

## 2. Skapa deployment på cbhcloud

| Inställning | Värde |
|---|---|
| Image | `ghcr.io/DITT_GITHUB_ANVÄNDARNAMN/garage-cbhcloud-quickstart:latest` |
| Image start arguments | `server` |
| Visibility | **Public** |
| Health check path | `/` |

**Miljövariabler:**

| Namn | Värde |
|---|---|
| `PORT` | `3900` |
| `GARAGE_RPC_SECRET` | output av `openssl rand -hex 32` |
| `GARAGE_ADMIN_TOKEN` | output av `openssl rand -hex 32` (spara detta värde!) |

**Persistent storage:**

| Namn | App path |
|---|---|
| `garage-data` | `/data` |

---

## 3. Initiera Garage

SSH:a in i containern:
```bash
ssh <deployment-namn>@deploy.cloud.cbh.kth.se
```

Hämta node ID:
```bash
garage node id
```

Tilldela layout (ersätt `<node-id>` med den fullständiga hex-strängen):
```bash
garage layout assign -z dc1 -c 1G <node-id>
garage layout apply --version 1
```

Skapa bucket och åtkomstnyckel:
```bash
garage bucket create ducklake
garage key create ducklake-key
garage bucket allow --read --write --owner ducklake --key ducklake-key
```

Spara **Key ID** (`GK...`) och **Secret key**.

---

## 4. Hämta Admin Token

Admin-tokenet injiceras via `envsubst` i `entrypoint.sh` och hamnar i `/tmp/garage.toml`.

> **OBS:** Använd alltid `/tmp/garage.toml`, inte `/etc/garage.toml`.  
> `/tmp/garage.toml` är den faktiska config som Garage kör med.

```bash
ssh <deployment-namn>@deploy.cloud.cbh.kth.se
cat /tmp/garage.toml | grep admin_token
```

Använd det exakta värdet som `GARAGE_ADMIN_TOKEN` i Access Manager-deploymentet.

---

## 5. Verifiera nginx-proxyn

När deploymentet är igång ska Garage-loggar visa:

```
S3 API server listening on http://[::]:3905
Admin API server listening on http://[::]:3903
```

Och healthcheck-requests ska gå via `127.0.0.1` (nginx):

```
10.42.x.x (via [::ffff:127.0.0.1]:xxxxx) GET /
```

---

## 6. Nginx-konfiguration

```nginx
server {
    listen 3900;

    location /v2/ {
        proxy_pass http://127.0.0.1:3903;   # Garage Admin API
    }

    location / {
        proxy_pass http://127.0.0.1:3905;   # Garage S3 API
    }
}
```

---

## Filer

| Fil | Syfte |
|---|---|
| `Dockerfile` | Multi-stage build: Garage-binär + Alpine + nginx |
| `garage.toml` | Garage-konfiguration med envsubst-platshållare |
| `nginx.conf` | Reverse proxy: 3900 → 3903 (Admin) / 3905 (S3) |
| `entrypoint.sh` | Kör envsubst, startar nginx, startar Garage |
