# Kubernetes deploy checklist (GitHub Actions + Helm)

Use this as the single entry point; each step links to or points at detailed docs.

## 1. GitHub Environment (e.g. `besties`)

**Repository → Settings → Environments → [environment] → Environment secrets**

| Secret | Purpose |
|--------|---------|
| `KUBECONFIG_FILE` | Base64-encoded kubeconfig for `helm`/`kubectl` (see deploy workflow). |
| `DB_PASSWORD` | Postgres password; substituted into `ops/<env>-deploy.tmpl.yaml` via `envsubst`. |
| `SOLR_ADMIN_USER` | Solr HTTP basic auth user (`extraEnvVars` Solr URLs and **`solrInit.adminUser`**). |
| `SOLR_ADMIN_PASSWORD` | Solr HTTP basic auth password (**`solrInit.adminPassword`**). |

The workflow substitutes `DB_PASSWORD` and `SOLR_ADMIN_*` into `ops/besties-deploy.tmpl.yaml` via `envsubst` (one source for the app container and **`load-solr-config`**). **`solrInit.zkConnect`** is committed literally in that file (edit if your ZooKeeper DNS/chroot differs).

## 2. PostgreSQL (external cluster)

Dataverse does **not** create the database. On the server in **`ops/besties-deploy.tmpl.yaml`** (`DATAVERSE_DB_HOST` / `POSTGRES_SERVER`), create the **database** and **role** that match **`DATAVERSE_DB_NAME`**, **`DATAVERSE_DB_USER`**, and your **`DB_PASSWORD`** secret.

For **`demo-dataverse`** (hyphenated names), Postgres requires **quoted** identifiers, e.g.:

```sql
CREATE USER "demo-dataverse" WITH PASSWORD '…';
CREATE DATABASE "demo-dataverse" OWNER "demo-dataverse";
```

If you see `FATAL: database "demo-dataverse" does not exist`, this step was skipped.

## 3. Kubernetes cluster (same namespace as the Helm release)

Create these **before** (or right after namespace exists) so the chart can mount them.

| Secret / object | When needed | How |
|-----------------|-------------|-----|
| **`aws-s3-credentials`** | `awsS3.enabled: true` in values (e.g. besties) | Full walkthrough: **[`ops/aws-s3-kubernetes-setup.md`](aws-s3-kubernetes-setup.md)** (`kubectl create secret generic …`, keys `credentials` + `config`). |
| **`dataverse-admin-api-key`** (optional) | Only if you mount a superuser API token on the pod/Jobs | **[`ops/dataverse-admin-api-key-kubernetes.md`](dataverse-admin-api-key-kubernetes.md)** — chart does **not** require this for a basic deploy. |
| **ConfigMap `dataverse-besties-solr-conf`** | **`solrInit`** is on for besties | **[`ops/solr-init-setup.md`](solr-init-setup.md)** — **`ops/fetch-dataverse-solr-conf.sh`** (IQSS **`conf/solr`**) then **`ops/create-solr-conf-configmap.sh`**. Solr admin creds: GitHub **`SOLR_ADMIN_*`** via envsubst. |

**Namespace:** Match whatever you deploy with (default from workflow: `<repo-name>-<environment>`, e.g. `demo-dataverse-besties`).

## 4. Run deploy

**Actions → Deploy → Run workflow** (branch + environment). The job renders `ops/<environment>-deploy.yaml` from the `.tmpl` and runs `bin/helm_deploy`.

## 5. Related docs

- **S3 + IAM + Secret shape:** [`ops/aws-s3-kubernetes-setup.md`](aws-s3-kubernetes-setup.md)  
- **Superuser API token Secret (optional automation):** [`ops/dataverse-admin-api-key-kubernetes.md`](dataverse-admin-api-key-kubernetes.md)  
- **Solr init (`solrInit`, ZK, ConfigMap):** [`ops/solr-init-setup.md`](solr-init-setup.md)  
- **Helm values template (Postgres, Solr URLs, ingress, S3, solrInit):** [`ops/besties-deploy.tmpl.yaml`](besties-deploy.tmpl.yaml) (copy/adapt for other env names)  
- **README (overview, Compose vs Helm):** [`README.md`](../README.md) (Helm / Kubernetes sections)
