# Kubernetes deploy checklist (GitHub Actions + Helm)

Use this as the single entry point; each step links to or points at detailed docs.

## 1. GitHub Environment (e.g. `besties`)

**Repository → Settings → Environments → [environment] → Environment secrets**

| Secret | Purpose |
|--------|---------|
| `KUBECONFIG_FILE` | Base64-encoded kubeconfig for `helm`/`kubectl` (see deploy workflow). |
| `DB_PASSWORD` | Postgres password; substituted into `ops/<env>-deploy.tmpl.yaml` via `envsubst`. |
| `SOLR_ADMIN_USER` | Solr HTTP basic auth user (embedded in Solr URL lines in the tmpl). |
| `SOLR_ADMIN_PASSWORD` | Solr HTTP basic auth password. |

No separate `SOLR_AUTH_PREFIX` secret—the workflow substitutes `SOLR_ADMIN_USER` / `SOLR_ADMIN_PASSWORD` directly.

## 2. Kubernetes cluster (same namespace as the Helm release)

Create these **before** (or right after namespace exists) so the chart can mount them.

| Secret / object | When needed | How |
|-----------------|-------------|-----|
| **`aws-s3-credentials`** | `awsS3.enabled: true` in values (e.g. besties) | Full walkthrough: **[`ops/aws-s3-kubernetes-setup.md`](aws-s3-kubernetes-setup.md)** (`kubectl create secret generic …`, keys `credentials` + `config`). |
| **`dataverse-admin-api-key`** (optional) | Only if you mount a superuser API token on the pod/Jobs | **[`ops/dataverse-admin-api-key-kubernetes.md`](dataverse-admin-api-key-kubernetes.md)** — chart does **not** require this for a basic deploy. |
| **Solr conf ConfigMap** + optional **Solr admin Secret** | Only if you enable **`solrInit`** in Helm values | ConfigMap: Dataverse `solr` `conf/` files (see [Dataverse Solr prerequisites](https://guides.dataverse.org/en/latest/installation/prerequisites.html#solr)). Init container auth: Secret with keys **`SOLR_ADMIN_USER`** / **`SOLR_ADMIN_PASSWORD`**, or set `solrInit.adminUser` / `adminPassword` in values (avoid committing passwords). |

**Namespace:** Match whatever you deploy with (default from workflow: `<repo-name>-<environment>`, e.g. `demo-dataverse-besties`).

## 3. Run deploy

**Actions → Deploy → Run workflow** (branch + environment). The job renders `ops/<environment>-deploy.yaml` from the `.tmpl` and runs `bin/helm_deploy`.

## 4. Related docs

- **S3 + IAM + Secret shape:** [`ops/aws-s3-kubernetes-setup.md`](aws-s3-kubernetes-setup.md)  
- **Superuser API token Secret (optional automation):** [`ops/dataverse-admin-api-key-kubernetes.md`](dataverse-admin-api-key-kubernetes.md)  
- **Helm values template (Postgres, Solr URLs, ingress, S3):** [`ops/besties-deploy.tmpl.yaml`](besties-deploy.tmpl.yaml) (copy/adapt for other env names)  
- **README (overview, Compose vs Helm):** [`README.md`](../README.md) (Helm / Kubernetes sections)
