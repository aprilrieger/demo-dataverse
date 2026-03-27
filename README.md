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

### Tenant branding (repeatable on every `up`)

Installation branding (installation name, navbar logo, custom header/home/footer/CSS, navbar URLs) is driven by **`branding/branding.env`** and static files under **`branding/docroot/`**. In the **gdcc/dataverse** image, **`/logos/*`** is *not* served from Payara’s `domains/domain1/docroot`; `glassfish-web.xml` sends it to **`DATAVERSE_FILES_DOCROOT`** (default **`/dv/docroot`**). Compose bind-mounts **`branding/docroot/logos/navbar`** to **`/dv/docroot/logos/navbar`** so `/logos/navbar/logo.png` resolves (the rest of `/dv/docroot/logos/` is left for theme uploads). **Dataset uploads** use a different path (**`/dv/uploads`** via `DATAVERSE_FILES_UPLOADS`)—that is temp upload processing space, not where you put the navbar logo.

1. After first boot, create a **superuser API token** in the UI and save it **on one line** in **`secrets/api/key`** (or set **`DATAVERSE_API_TOKEN`** in `.env`—avoid committing real tokens).
2. **`docker compose up -d`** runs **`dev_branding`** once after **`dev_bootstrap`** completes; it executes **`scripts/apply-branding.sh`** and issues idempotent Admin API `PUT`s.
3. Compose does **not** re-run finished one-shot services on later `up`s. To apply branding again after you change `branding.env` or assets, run **`docker compose run --rm dev_branding`** or **`./bin/dev-up`** (brings the stack up, then re-runs branding).

Requires Docker Compose v2 **with `depends_on: condition: service_completed_successfully`**. See the [Dataverse branding guide](https://guides.dataverse.org/en/latest/installation/config.html#branding-your-installation) for path semantics.

**Broken image in the header:** Dataverse can show **two** logos: the small **navbar** image (`:LogoCustomizationFile` → e.g. `/logos/navbar/logo.png`) and a separate **root collection theme** banner (`/logos/<id>/<theme file>`). A missing theme file produces a broken `<img>` even when your navbar file is fine. This repo sets **`DISABLE_ROOT_DATAVERSE_THEME=true`** in `branding/branding.env` by default when you use a navbar logo; re-run `docker compose run --rm dev_branding` after changing it. Confirm the asset loads with `curl -sI "http://localhost:8080/logos/navbar/logo.png"` (or through Traefik on port 80).

### `config/` and `triggers/`

- **`config/schema.xml`** — Solr schema used by **Docker Compose** (bind-mounted into **`coronawhy/solr`**). The image still provides **`solrconfig.xml`**, **`lang/`**, **`stopwords.txt`**, etc. For **Kubernetes `solrInit`**, build a **full** conf directory with **`ops/fetch-dataverse-solr-conf.sh`** (IQSS **`conf/solr`** from Git + merged Solr **8.11** **`_default`** resources + schema patch); use **`OVERLAY_REPO_SCHEMA=1`** to fold **`./config/schema.xml`** into that bundle. Details: **`ops/solr-init-setup.md`**.
- **`triggers/`** — SQL/Python helpers mounted where the compose file expects them.

### Helm / Kubernetes: deploy checklist

**[`ops/kubernetes-deploy-checklist.md`](ops/kubernetes-deploy-checklist.md)** — GitHub Environment secrets, cluster Secrets (S3, Solr conf ConfigMap for **`solrInit`**, optional API token), then run Actions → Deploy.

### Helm / Kubernetes: AWS S3 secrets

For cluster deploys, object storage uses an out-of-band Kubernetes Secret and Helm `awsS3` values. Step-by-step (bucket, IAM, `kubectl create secret`, values alignment) is in **`ops/aws-s3-kubernetes-setup.md`**.

### Helm / Kubernetes: production branding

This chart does **not** automate installation branding in the cluster. For production, configure branding and uploaded assets through the **Dataverse UI** (see the [installation branding guide](https://guides.dataverse.org/en/latest/installation/config.html#branding-your-installation)). Local **Docker Compose** still uses **`branding/`**, **`scripts/apply-branding.sh`**, and **`dev_branding`** as described above.

### Helm / Kubernetes: superuser API token

To automate admin or native API calls (settings, collections, scripts), store a superuser API token in a cluster Secret and wire it with `extraEnvFrom` / `secretKeyRef`. See **`ops/dataverse-admin-api-key-kubernetes.md`**.

---

## Services (overview)

| Service | Role |
|---------|------|
| **reverse-proxy** | Traefik: routes `www.${traefikhost}` / `${traefikhost}` to Dataverse, optional TLS with ACME. |
| **postgres** | Application database. |
| **solr** | Search index (`coronawhy/solr` + `./config/schema.xml`; cluster **`solrInit`** uses **`ops/fetch-dataverse-solr-conf.sh`** — **`ops/solr-init-setup.md`**). |
| **minio** | S3-compatible object storage (optional for basic UI flows). |
| **dataverse** | GDCC Dataverse on Payara (`gdcc/dataverse:${VERSION}`), `platform: linux/amd64`. |
| **dev_bootstrap** | One-shot **GDCC configbaker** `bootstrap.sh dev`: root Dataverse, metadata, **`dataverseAdmin`**, FAKE DOI defaults. Waits until Dataverse's **`/api/info/version`** returns **200**. |
| **dev_branding** | One-shot after bootstrap: applies **`branding/branding.env`** via Admin API. Re-run with **`docker compose run --rm dev_branding`** or **`./bin/dev-up`**. |
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
