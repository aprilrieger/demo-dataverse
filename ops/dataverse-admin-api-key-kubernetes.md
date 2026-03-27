# Kubernetes Secret: Dataverse superuser API token

Use a **superuser** API token to call the [Native API](https://guides.dataverse.org/en/latest/api/native-api.html) and [Admin API](https://guides.dataverse.org/en/latest/api/admin.html) from automation (for example `PUT /api/admin/settings/...`, collection updates, or CI jobs). Store the token in a Kubernetes **Secret** in the **same namespace** as the workload that needs it (Dataverse pod, a Job, or an operator sidecar).

**Do not** put the token in Helm `values.yaml` or commit it to git: Helm stores release values in the cluster and they can appear in logs.

---

## Predictable tokens, Docker, and `secrets/api/key`

Dataverse **does not** support configuring the superuser API token to a fixed value. Tokens are issued by the application and stored in the database (see [API Tokens and Authentication](https://guides.dataverse.org/en/latest/api/auth.html)). There is no JVM option or `/secrets/...` file that Payara reads to set “the” API key.

**Practical approach for local / seeded automation**

1. **One-time:** Sign in as the bootstrap superuser (**`dataverseAdmin`** / **`admin1`** in this repo), create an API token in the UI, and paste it into a file your scripts read.
2. **Stable path in Docker Compose:** The Dataverse service already mounts **`./secrets` → `/secrets`**. Use e.g. **`secrets/api/key`** as a **single line** containing only the token (no quotes). Seed or `curl` wrappers can use:
   `export DATAVERSE_API_TOKEN="$(tr -d '[:space:]' < /secrets/api/key)"`  
   when running **inside** the container, or the same path on the host from the repo root. Dataverse ignores this file unless **your** tooling reads it.
3. **Do not commit real tokens.** Keep a placeholder in git if you want, and override locally, or add `secrets/api/key` to `.gitignore` and document that each developer copies a template once.

**Related (not an API token): [`:BuiltinUsersKey`](https://guides.dataverse.org/en/latest/installation/config.html#builtinuserskey)** — Shared secret for **`POST /api/builtin-users`**. In this repo, `init.d/01-persistent-id.sh` sets it from **`BUILTIN_USERS_KEY`** (default **`burrito`**). Override via `.env` / Compose `env_file` if you want a different value. That key creates **local accounts** via API; it does **not** replace a superuser API token for admin endpoints.

**Unsupported / fragile:** Inserting rows directly into Postgres for API tokens is possible in theory but ties you to internal schema and hashing details per Dataverse version—avoid for demos unless you own the maintenance cost.

---

## 1. Obtain a superuser token

1. Deploy Dataverse and sign in as a **superuser** (this repo’s compose bootstrap uses **`dataverseAdmin`** / **`admin1`** until you change it).
2. In the UI: **user menu → API Token** (wording may vary slightly by version), then create a token with **no expiration** or a rotation policy you can automate.
3. Copy the token once; Dataverse does not show the full secret again.

There is no stable “bootstrap prints API token” path across all installs; one short UI or admin step after first boot is normal. After you have the token, everything below is non-interactive.

---

## 2. Create the Secret (correct namespace)

Pick a Secret name (examples below use **`dataverse-admin-api-key`**). Pick an **environment variable name** for the pod; examples use **`DATAVERSE_API_TOKEN`** so scripts can do:

`curl -H "X-Dataverse-key: $DATAVERSE_API_TOKEN" ...`

The **key** inside the Kubernetes Secret object must be a valid environment variable name when you use `envFrom` / `secretRef` (use letters, digits, underscore; leading digit not recommended).

```bash
NAMESPACE="your-namespace-here"   # same namespace as the Helm release or Job

kubectl create secret generic dataverse-admin-api-key \
  --namespace="$NAMESPACE" \
  --from-literal=DATAVERSE_API_TOKEN='paste-token-here'
```

**From a file** (avoid shell history; keep the file out of git):

```bash
# token.txt contains one line: the raw token, no quotes
kubectl create secret generic dataverse-admin-api-key \
  --namespace="$NAMESPACE" \
  --from-file=DATAVERSE_API_TOKEN=./token.txt
```

**Update or replace** an existing Secret:

```bash
kubectl create secret generic dataverse-admin-api-key \
  --namespace="$NAMESPACE" \
  --from-literal=DATAVERSE_API_TOKEN='paste-token-here' \
  --dry-run=client -o yaml | kubectl apply -f -
```

**Verify** (only that the key exists, not the value):

```bash
kubectl get secret dataverse-admin-api-key -n "$NAMESPACE" -o jsonpath='{.data}' | jq 'keys'
# Expect: ["DATAVERSE_API_TOKEN"]  (or whatever key name you chose)
```

---

## 3. Expose the token to pods (Helm chart)

The **`demo-dataverse`** chart does not mount this Secret by default. Use **`extraEnvFrom`** in your values file so the Dataverse container receives the variable (or use the same pattern on a separate Job manifest).

```yaml
extraEnvFrom:
  - secretRef:
      name: dataverse-admin-api-key
```

The Payara/Dataverse application **does not** read `DATAVERSE_API_TOKEN` automatically; this is for **your** `init.d` scripts, startup hooks, or external Jobs that run inside or against the cluster. If you only need the token for a **CronJob** that calls the public Ingress URL, mount the same Secret on that Job only—there is no need to give it to the main Dataverse Deployment.

**Optional: single key with `secretKeyRef`** (if you prefer not to import every key from a shared Secret):

```yaml
extraEnvVars:
  - name: DATAVERSE_API_TOKEN
    valueFrom:
      secretKeyRef:
        name: dataverse-admin-api-key
        key: DATAVERSE_API_TOKEN
```

---

## 4. Using the token against the cluster

- From a pod in the cluster, use the in-cluster Service URL (see your Helm release), e.g. `http://demo-dataverse.<namespace>.svc.cluster.local` or whatever host your values set, with header **`X-Dataverse-key`**.
- From your laptop, use the same token against the Ingress URL over HTTPS.

Example:

```bash
curl -sS -H "X-Dataverse-key: $DATAVERSE_API_TOKEN" \
  "https://your-dataverse-host/api/admin/settings/:InstallationName"
```

---

## 5. GitHub Actions and hygiene

- Store the token in a **GitHub Actions secret** (e.g. `DATAVERSE_API_TOKEN`) if a workflow must call the API or run `kubectl` to patch the Secret.
- **Never** echo the token in CI logs; use masked secrets and avoid `curl -v` in shared workflows.
- Rotate by generating a new token in the Dataverse UI, updating the Kubernetes Secret (`kubectl apply` with `--dry-run=client` pattern above), and revoking the old token if the UI allows.

---

## 6. Optional alternatives

- **External Secrets Operator** / **Secrets Store CSI** / cloud secret manager: sync into a Secret named `dataverse-admin-api-key` with the same data key (`DATAVERSE_API_TOKEN`); no chart change required if you still use `extraEnvFrom` or `secretKeyRef`.
- **Sealed Secrets**: seal a `Secret` manifest that contains `DATAVERSE_API_TOKEN` and commit the sealed resource; the cluster controller materializes the real Secret at deploy time.

---

## Reference

- Dataverse API authentication: [API intro — Authentication](https://guides.dataverse.org/en/latest/api/intro.html#authentication)
- Chart escape hatches: `extraEnvFrom`, `extraEnvVars` in `charts/demo-dataverse/values.yaml`
