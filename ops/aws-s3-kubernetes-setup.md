# Manual setup: AWS S3 for Helm-deployed Dataverse

This stack configures Dataverse’s S3 file store via **`006-s3-aws-storage.sh`**, which the Helm chart embeds when **`awsS3.enabled`** is true and mounts at **`/opt/payara/scripts/init.d/006-s3-aws-storage.sh`**. That path is where the **`gdcc/dataverse` base image entrypoint** sources scripts **before** Payara starts (see [Base image — Entry & Extension Points](https://guides.dataverse.org/en/latest/container/base-image.html#base-entrypoint)). The script runs only when **`aws_bucket_name`** is set (the chart sets it from **`awsS3.bucketName`**) and expects AWS CLI-style files under **`/secrets/aws-cli/.aws/`** (`credentials` and `config`). The chart mounts your Kubernetes **Secret** there when **`awsS3.enabled`** is true.

**Compose / custom mounts:** If you bind-mount this repo’s **`init.d/`** at **`/opt/payara/init.d`**, that alone does **not** run **`006`** on boot (the entrypoint uses **`/opt/payara/scripts/init.d/`**). Mount **`006-s3-aws-storage.sh`** into **`/opt/payara/scripts/init.d/`** (file bind-mount is fine) or copy the script there in a derived image.

Use this checklist when deploying with values like `ops/besties-deploy.tmpl.yaml` (secret name **`aws-s3-credentials`**, bucket **`demo-dataverse`**, region endpoint **`https://s3.us-west-2.amazonaws.com`**). Adjust names, namespace, and region to match your environment.

---

## 1. AWS: S3 bucket

1. In **AWS Console → S3** (or IaC), create a bucket (e.g. `demo-dataverse`).
2. Choose the **Region** you will use in the endpoint URL (e.g. `us-west-2`).
3. Block Public Access: leave **enabled** unless you deliberately need public objects; Dataverse can use pre-signed URLs or your chosen download behavior.
4. Optional: enable **versioning** or **encryption** per your retention policy.

---

## 2. AWS: IAM for Dataverse

1. Create an **IAM user** (or role if you later use IRSA / workload identity; this chart currently uses **static keys** in a Secret).  
   **Suggested user name:** **`s3-demo-dataverse`** (dedicated to this bucket; not your personal SSO/assume-role identity).

   ```bash
   AWS_PROFILE=n8 aws iam create-user --user-name s3-demo-dataverse
   ```

   Attach the policy from step 2 (Console **IAM → Users → s3-demo-dataverse → Add permissions**, or `put-user-policy` / `attach-user-policy`).

2. Attach a policy that allows Dataverse to read/write objects in that bucket. A minimal example (replace bucket name and optionally tighten `Resource` ARNs):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListBucket",
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
      "Resource": "arn:aws:s3:::demo-dataverse"
    },
    {
      "Sid": "ObjectRW",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts"
      ],
      "Resource": "arn:aws:s3:::demo-dataverse/*"
    }
  ]
}
```

3. For that IAM user, create **access keys**. Save **Access key ID** and **Secret access key** immediately (secret is shown only once).

   **Console:** user → **Security credentials** → **Create access key**.

   **CLI:**

   ```bash
   AWS_PROFILE=n8 aws iam create-access-key --user-name s3-demo-dataverse
   ```

   Copy the keys into **`.aws-dataverse-s3/credentials`** (see §3); that path is **gitignored** in this repo.

---

## 3. Local files: `credentials` and `config`

Create two files that mirror the usual `~/.aws` layout. The **profile name** in `credentials` must match Helm **`awsS3.profile`** (default **`default`**).

**`credentials`** (example):

```ini
[default]
aws_access_key_id = AKIAxxxxxxxxxxxxxxxx
aws_secret_access_key = yourSecretAccessKey
```

**`config`** (example for `us-west-2`):

```ini
[default]
region = us-west-2
```

- **`awsS3.endpointUrl`** in Helm (e.g. `https://s3.us-west-2.amazonaws.com`) is passed to Dataverse as **`custom-endpoint-url`**; keep it consistent with the bucket’s region.
- If you use a named profile (e.g. `[dataverse]`), set **`awsS3.profile`** in values to that name and use the same section name in both files.

---

## 4. Kubernetes: create the Secret (correct namespace)

Create the Secret in the **same namespace** as the Helm release (e.g. `demo-dataverse-besties` if that is how you deploy).

Default key names expected by the chart are **`credentials`** and **`config`** (see `awsS3.secretKeys` in `charts/demo-dataverse/values.yaml`). The Secret’s **data keys** must match those names.

From the directory containing your two files:

```bash
NAMESPACE="your-namespace-here"   # e.g. demo-dataverse-besties

kubectl create secret generic aws-s3-credentials \
  --namespace="$NAMESPACE" \
  --from-file=credentials=./credentials \
  --from-file=config=./config
```

**Update existing secret** (same keys):

```bash
kubectl create secret generic aws-s3-credentials \
  --namespace="$NAMESPACE" \
  --from-file=credentials=./credentials \
  --from-file=config=./config \
  --dry-run=client -o yaml | kubectl apply -f -
```

**Verify** (values only, not raw secrets):

```bash
kubectl get secret aws-s3-credentials -n "$NAMESPACE" -o jsonpath='{.data}' | jq 'keys'
# Expect: "config", "credentials"
```

---

## 5. Helm values alignment

In your values file (e.g. rendered `ops/besties-deploy.yaml` from the template):

| Value | Must match |
|--------|------------|
| `awsS3.enabled` | `true` |
| `awsS3.existingSecret` | Kubernetes Secret name (e.g. `aws-s3-credentials`) |
| `awsS3.bucketName` | Real S3 bucket name |
| `awsS3.endpointUrl` | Regional S3 endpoint for that bucket |
| `awsS3.profile` | Section name in `credentials` / `config` (e.g. `default`) |
| `awsS3.secretKeys.credentials` / `config` | **Keys** inside the Kubernetes Secret (defaults: `credentials`, `config`) |

Do **not** duplicate `aws_bucket_name`, `aws_endpoint_url`, or `aws_s3_profile` in `extraEnvVars` unless you intend to override the chart-managed env vars.

---

## 6. After deploy

1. Confirm the Dataverse pod has both mounts:

   ```bash
   kubectl get pod -n "$NAMESPACE" -l app.kubernetes.io/component=primary -o jsonpath='{.items[0].metadata.name}' | xargs -I{} kubectl describe pod -n "$NAMESPACE" {}
   ```

   You should see **`/secrets/aws-cli/.aws`** (Secret volume) and **`/opt/payara/scripts/init.d/006-s3-aws-storage.sh`** (ConfigMap **`subPath`**).

2. In pod logs, the entrypoint should mention running the S3 script, e.g. `[Entrypoint] running /opt/payara/scripts/init.d/006-s3-aws-storage.sh` (exact wording may vary).

3. Confirm JVM options were applied (optional): from a shell inside the pod, run Payara’s **`asadmin list-jvm-options`** with the admin credentials your image uses (defaults are documented in the [base image](https://guides.dataverse.org/en/latest/container/base-image.html)), and look for **`-Ddataverse.files.S3.`** and **`-Ddataverse.files.storage-driver-id`**. If you prefer not to use `asadmin`, rely on steps 2 and 4 plus absence of S3 **`AccessDenied`** errors in logs.

4. **End-to-end:** In the Dataverse UI, upload a small test file, then list the bucket:

   ```bash
   aws s3 ls "s3://${BUCKET}/" --recursive | head
   ```

   You should see new object keys (paths depend on Dataverse version and dataset layout).

5. **`:DownloadMethods`:** The script cannot call the Admin API during init (Payara is not up yet). If you need **`native/http`** downloads with S3 redirect, set **`DownloadMethods`** once after install (Admin → Settings or API) or leave your existing site default.

6. Check startup logs for Payara/Dataverse for S3 or AWS SDK errors (wrong region, `AccessDenied`, wrong bucket name).

---

## 7. GitHub Actions / repository hygiene

- **No GitHub secret is required** for S3 **if** you only use the Kubernetes Secret above; CI applies Helm with values that reference `existingSecret`.
- **`MINIO_ROOT_PASSWORD`** is no longer used by the deploy workflow for this chart; you can remove it from the GitHub **Environment** secrets if it is unused elsewhere.
- Never commit `credentials`, `config`, or rendered files containing real keys. Keep `ops/besties-deploy.yaml` gitignored (see `.gitignore`) if it is generated locally with secrets.

---

## 8. Optional alternatives

- **External Secrets Operator** / **Sealed Secrets**: create the same Kubernetes Secret shape (keys `credentials` and `config` with file contents) from your secret manager; the chart does not need changes if key names match.
- **IRSA (EKS)** / workload identity: Dataverse’s init script today copies **files** from `/secrets/aws-cli/.aws`. Moving to pod identity would require a different integration (not covered by the current `006-s3-aws-storage.sh` path).

---

## Reference

- Dataverse S3 config (concepts): [Installation — S3 storage](https://guides.dataverse.org/en/latest/installation/config.html#s3-storage)
- Chart wiring: `charts/demo-dataverse/templates/deployment.yaml` (`awsS3` env + Secret mount + ConfigMap **`subPath`** for `006`)
- Init script (chart copy): `charts/demo-dataverse/files/006-s3-aws-storage.sh` (kept in sync with `init.d/006-s3-aws-storage.sh` for Compose)
