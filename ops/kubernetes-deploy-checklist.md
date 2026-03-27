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
| **ConfigMap `dataverse-besties-solr-conf`** | **`solrInit`** is on for besties | **[`ops/solr-init-setup.md`](solr-init-setup.md)** — run **`ops/fetch-dataverse-solr-conf.sh`** (IQSS **`conf/solr`**, merge **8.11.2** **`_default`** resources, patch **`schema.xml`** + **`solrconfig.xml`** for Bitnami Solr **8.11**), then **`ops/create-solr-conf-configmap.sh`** on **`dv-solr-conf/`**. Solr admin creds: GitHub **`SOLR_ADMIN_*`** via envsubst. |

**Namespace:** Match whatever you deploy with (default from workflow: `<repo-name>-<environment>`, e.g. `demo-dataverse-besties`).

## 4. Run deploy

**Actions → Deploy → Run workflow** (branch + environment). The job renders `ops/<environment>-deploy.yaml` from the `.tmpl` and runs `bin/helm_deploy`.

## 5. After deploy: public URL (`siteUrl` / `fqdn`)

The **gdcc/dataverse** image does **not** run this repo’s **`init.d/04-setdomain.sh`** unless you mount **`./init.d`** via the chart’s **`configMap`** (Compose does; default Helm values do not). Set the public hostname with **`dataverse_*`** env vars so **`init_2_configure.sh`** injects Payara system properties (see [Application image tunables](https://guides.dataverse.org/en/latest/container/app-image.html#tunables)):

- **`dataverse_siteUrl`** — full public base URL, e.g. `https://demo-dataverse.notch8.cloud`
- **`dataverse_fqdn`** — hostname only, e.g. `demo-dataverse.notch8.cloud`

**`besties-deploy.tmpl.yaml`** includes these. If **`DATAVERSE_URL`** is a full `https://…` URL while a script expects **`http://${DATAVERSE_URL}/api`**, bootstrap curls can break; use **`localhost:8080`** for in-pod API access and keep the public URL in **`dataverse_siteUrl`**.

If **`/`** still returns Dataverse “Page Not Found”, check **`https://<host>/api/info/version`**, pod logs for bootstrap errors, and the [Dataverse troubleshooting guide](https://guides.dataverse.org/en/latest/admin/troubleshooting.html).

## 6. Related docs

- **S3 + IAM + Secret shape:** [`ops/aws-s3-kubernetes-setup.md`](aws-s3-kubernetes-setup.md)  
- **Superuser API token Secret (optional automation):** [`ops/dataverse-admin-api-key-kubernetes.md`](dataverse-admin-api-key-kubernetes.md)  
- **Solr init (`solrInit`, ZK, ConfigMap):** [`ops/solr-init-setup.md`](solr-init-setup.md)  
- **Helm values template (Postgres, Solr URLs, ingress, S3, solrInit):** [`ops/besties-deploy.tmpl.yaml`](besties-deploy.tmpl.yaml) (copy/adapt for other env names)  
- **README (overview, Compose vs Helm):** [`README.md`](../README.md) (Helm / Kubernetes sections)
