# Manual setup: AWS S3 for Helm-deployed Dataverse

This stack configures Dataverse’s S3 file store via `init.d/006-s3-aws-storage.sh`. That script runs only when **`aws_bucket_name`** is set and expects AWS CLI-style files under **`/secrets/aws-cli/.aws/`** (`credentials` and `config`). The Helm chart supplies those by mounting a Kubernetes **Secret** when **`awsS3.enabled`** is true.

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

3. For that IAM user, create **access keys** (Console: user → **Security credentials** → **Create access key**). Save **Access key ID** and **Secret access key** securely.

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

1. Confirm the Dataverse pod has the mount:

   ```bash
   kubectl describe pod -n "$NAMESPACE" -l app.kubernetes.io/component=primary | rg -n "aws-cli|/secrets/aws-cli"
   ```

2. Check startup logs for Payara/Dataverse and for errors from S3 (permissions, wrong region, wrong bucket).

3. In the Dataverse UI, upload a small test file and confirm it lands in the bucket (S3 console or AWS CLI `aws s3 ls s3://your-bucket/`).

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
- Chart wiring: `charts/demo-dataverse/templates/deployment.yaml` (`awsS3` env + volume mount)
- Init script: `init.d/006-s3-aws-storage.sh`
