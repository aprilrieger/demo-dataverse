# demo-dataverse

Local **Dataverse** stack for development and demos, using **Docker Compose** and official **[GDCC](https://github.com/IQSS/dataverse)** container images (Payara + Dataverse, Solr, PostgreSQL, MinIO, Traefik).

This repo is a trimmed, opinionated layout: **named volumes** for data (reset with `docker compose down -v`), a **committed `.env`**, and **`env_file: .env`** on every service so runtime configuration stays explicit.

---

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/) v2 (`docker compose` CLI)
- Enough RAM for Payara + Solr + Postgres (roughly **4 GB+** comfortable on Apple Silicon with `linux/amd64` emulation)

---

## Quick start

From the repository root:

```bash
docker compose up -d
```

First startup can take **several minutes** (image pulls, Payara boot, WAR deploy, then bootstrap). Watch progress:

```bash
docker compose logs -f dataverse
docker compose logs -f dev_bootstrap
```

When bootstrap finishes, open the UI (see below) and sign in with the **dev** admin user.

---

## URLs and logins

| What | URL | Notes |
|------|-----|--------|
| Dataverse (via Traefik) | [http://localhost/](http://localhost/) | Use **`http://`**, not `https://`, for local demo (`traefikhost=localhost`). |
| Dataverse (direct Payara) | [http://localhost:8080/](http://localhost:8080/) | Bypasses Traefik. |
| Payara admin | [http://localhost:4848/](http://localhost:4848/) | Default user **`admin`**; password from Payara / `secrets` (often **`admin`** in dev). |
| Traefik dashboard | [http://localhost:8089/](http://localhost:8089/) | API insecure mode enabled for local use. |
| Solr | [http://localhost:8983/](http://localhost:8983/) | Published on host for debugging. |
| Postgres | `localhost:5432` | User/password/database match `.env`. |

**Bootstrap admin (after `dev_bootstrap` succeeds):**

- **Username:** `dataverseAdmin`
- **Password:** `admin1`

(Passwords in **`.env`** and **`secrets/`** are for Postgres, Payara, etc.—not the same as this UI account.)

**Important:** Payara speaks **plain HTTP** on `8080`. Opening **`https://localhost:8080`** sends TLS to an HTTP listener and can produce **Grizzly / bad request** errors in logs. Prefer **`http://`**.

---

## Configuration

### `.env`

Variables live in **`.env`** at the repo root. Compose uses them for:

1. **Interpolation** in `docker-compose.yml` (e.g. `${VERSION}`, `${traefikhost}` on Traefik labels).
2. **Container environment** via the shared `env_file: .env` entry on each service.

Edit **`.env`** to change image tag (`VERSION`, `DOCKER_HUB`), hostnames (`hostname`, `traefikhost`), DB credentials, or **`useremail`** (Traefik ACME / Let's Encrypt). After changes, recreate affected services:

```bash
docker compose up -d --force-recreate
```

### `secrets/`

Payara-related password files used by the Dataverse image; mounted read-only into the container. Adjust if you change admin or DB bootstrap expectations.

### `init.d/`

Shell scripts run by the Dataverse container's startup flow (order by filename). Use this for extra JVM options, storage drivers, or post-boot tweaks. Scripts should match patterns from upstream [dataverse-docker](https://github.com/IQSS/dataverse-docker) / your image's docs.

### `config/` and `triggers/`

- **`config/schema.xml`** — Solr schema fragment mounted into the Solr image.
- **`triggers/`** — SQL/Python helpers mounted where the compose file expects them.

### Helm / Kubernetes: AWS S3 secrets

For cluster deploys, object storage uses an out-of-band Kubernetes Secret and Helm `awsS3` values. Step-by-step (bucket, IAM, `kubectl create secret`, values alignment) is in **`ops/aws-s3-kubernetes-setup.md`**.

---

## Services (overview)

| Service | Role |
|---------|------|
| **reverse-proxy** | Traefik: routes `www.${traefikhost}` / `${traefikhost}` to Dataverse, optional TLS with ACME. |
| **postgres** | Application database. |
| **solr** | Search index (`coronawhy/solr` + mounted `schema.xml`). |
| **minio** | S3-compatible object storage (optional for basic UI flows). |
| **dataverse** | GDCC Dataverse on Payara (`gdcc/dataverse:${VERSION}`), `platform: linux/amd64`. |
| **dev_bootstrap** | One-shot **GDCC configbaker** `bootstrap.sh dev`: root Dataverse, metadata, **`dataverseAdmin`**, FAKE DOI defaults. Waits until Dataverse's **`/api/info/version`** returns **200**. |
| **whoami** | Tiny Traefik test service. |

Docker network **`dataverse_traefik`** is created by Compose (no manual `docker network create`).

---

## Data and reset

Persistent state uses **named volumes** (Postgres, Solr data, MinIO, Dataverse file stores, Traefik ACME store). To **wipe all of that** and start clean:

```bash
docker compose down -v
docker compose up -d
```

**Not** removed: **`secrets/`**, **`init.d/`**, **`config/`**, **`triggers/`**, or **`.env`**.

Re-run bootstrap after a wipe (usually automatic on `up -d` via **`dev_bootstrap`**). If it already ran on a non-empty DB, see **Troubleshooting**.

---

## Common developer commands

```bash
# Service status
docker compose ps

# Logs
docker compose logs -f dataverse
docker compose logs -f dev_bootstrap

# Shell inside Dataverse container
docker compose exec dataverse bash

# API smoke test (from host)
curl -sS http://localhost:8080/api/info/version

# Redeploy / Payara (example; password in secrets)
# docker compose exec dataverse ...
```

---

## Troubleshooting

| Symptom | Things to check |
|---------|------------------|
| **`dev_bootstrap` fails** waiting on `/api/info/version` | **`docker compose logs dataverse`**: deploy errors (DB, Solr, `ConfigCheckService`). On ARM Mac, first deploy is slow; healthcheck + `TIMEOUT=20m` are already set. |
| **404** on `/api/info/version` while Payara is up | WAR not finished deploying yet, or deploy failed—check logs. |
| **"Page Not Found"** in the Dataverse UI | Bootstrap did not complete; ensure **`dev_bootstrap`** exited successfully and DB is not half-seeded. |
| **Traefik 404** on `http://localhost/` | Host rules use `www.${traefikhost}` **or** `${traefikhost}`; keep **`traefikhost`** in `.env` aligned with how you browse (e.g. `localhost`). |
| **Solr / DB errors** after upgrade | `docker compose down -v` and bring the stack up again if you intend a full reset. |

---

## Security note

**`.env`** and **`secrets/`** contain **development defaults**. Do not expose this stack to the internet without hardening (real TLS, secrets management, API blocking, etc.). For a **public Git repo**, prefer private env injection (CI secrets, `.env` gitignored) instead of committing credentials.

---

## Upstream and license

- **Dataverse:** [IQSS/dataverse](https://github.com/IQSS/dataverse) — see upstream license and citation guidance.
- **Container images:** [GDCC on Docker Hub](https://hub.docker.com/u/gdcc) (`gdcc/dataverse`, `gdcc/configbaker`).
- This layout derives from community **[dataverse-docker](https://github.com/IQSS/dataverse-docker)**-style compose and init patterns; verify license terms if you redistribute.

---

## Version pin

Images are pinned in **`.env`** (e.g. `VERSION=6.10.1-noble-r0`). Bump **`VERSION`** (and test Solr/schema compatibility) when upgrading Dataverse.
