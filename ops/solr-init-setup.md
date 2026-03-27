# Solr init (`solrInit`)

**Besties** (`ops/besties-deploy.tmpl.yaml`) has **`solrInit.enabled: true`**. The chart runs a **pre-start initContainer** that:

1. Waits for Solr’s HTTP API  
2. Runs **`solr zk upconfig`** to load a **Dataverse** configset into **ZooKeeper**  
3. Creates the **`dataverse`** collection if it does not exist (shards / replicas from Helm values)

Other environments can turn the same behavior on in **`charts/demo-dataverse/values.yaml`** or a values overlay.

For **besties**, **`solrInit.zkConnect`** is set **in git** in **`ops/besties-deploy.tmpl.yaml`** (same string your Solr nodes use). Edit that value when ZK hostnames or chroot change; the deploy workflow does **not** use a **`ZK_CONNECT`** secret.

---

## 1. ZooKeeper connect string (`solrInit.zkConnect`)

Use the same string your Solr nodes use for ZK (including **chroot** if you use one), for example:

```text
zk-0.zk-hs.solr.svc.cluster.local:2181,zk-1.zk-hs.solr.svc.cluster.local:2181,zk-2.zk-hs.solr.svc.cluster.local:2181/solr
```

Replace hostnames with your cluster’s ZooKeeper Service DNS names and ports. In **besties**, update **`zkConnect`** under **`solrInit`** in **`ops/besties-deploy.tmpl.yaml`**.

### If you see `UnknownHostException: zk-0.zk-hs.solr.svc.cluster.local`

The value in git is an **example**, not your real ZK. Find the string your Solr deployment already uses (it must be identical):

1. **From a Solr pod** (namespace and label set vary by chart):

   ```bash
   kubectl get pods -n solr -l app.kubernetes.io/name=solr
   kubectl exec -n solr -it statefulset/YOUR_SOLR_STATEFULSET -- printenv | grep -i zk
   ```

   Look for variables like **`SOLR_ZK_HOSTS`**, **`ZK_HOST`**, **`ZOO_SERVERS`**, or **`SOLR_HOST`**-style ZK lists (Bitnami often sets **`SOLR_ZK_HOSTS`** or embeds ZK in **`SOLR_JAVA_MEM`** / start scripts — check **`kubectl describe pod`** and the Solr Helm values you used).

2. **From ZooKeeper Services**: list ZK-related Services and StatefulSets, then build **`host:2181`** entries (use the **headless** Service DNS for StatefulSet pods: **`pod-name.headless-service.namespace.svc.cluster.local`**).

3. **Chroot**: if Solr uses a ZK chroot (e.g. **`/solr`**), append it once at the end of the whole string: **`host1:2181,host2:2181/solr`**.

If your Solr is **standalone** (no ZooKeeper), **`solr zk upconfig`** / SolrCloud init is the wrong model — turn off **`solrInit`** and manage the core with your Solr chart instead.

---

## 2. Solr `conf/` directory (Dataverse release)

You need the **official** Solr files for your Dataverse version: at minimum **`solrconfig.xml`** and **`schema.xml`** (for IQSS **v6.10.1** the Git tree is exactly three files under **`conf/solr/`** — no separate **`lang/`** tree in-repo).

### A — Recommended: IQSS Git tag (matches Dataverse)

Download the same **`conf/solr/`** files your release ships with:

```bash
chmod +x ops/fetch-dataverse-solr-conf.sh
./ops/fetch-dataverse-solr-conf.sh
# Optional: use this repo’s customized schema (Compose bind-mount source):
#   OVERLAY_REPO_SCHEMA=1 ./ops/fetch-dataverse-solr-conf.sh
# Optional: other Dataverse version (Git tag, e.g. v6.9.0):
#   DATAVERSE_GIT_REF=v6.9.0 ./ops/fetch-dataverse-solr-conf.sh

./ops/create-solr-conf-configmap.sh "$(pwd)/dv-solr-conf" demo-dataverse-besties
```

Source in GitHub: **[`IQSS/dataverse` → `conf/solr/`](https://github.com/IQSS/dataverse/tree/v6.10.1/conf/solr)** (replace **`v6.10.1`** in the URL if you change **`DATAVERSE_GIT_REF`**). Keep the tag aligned with your **`gdcc/dataverse`** image version.

**Solr 8.11 (Bitnami):** IQSS **`v6.10.1`** `schema.xml` includes a few **`<tokenizer name="standard"/>`** / **`<filter name="stop"`** lines that Solr **8.11** rejects (*missing mandatory attribute `class`*). **`fetch-dataverse-solr-conf.sh`** runs **`ops/patch-dataverse-schema-solr811.sh`** automatically. If you built **`dv-solr-conf`** by hand, run **`./ops/patch-dataverse-schema-solr811.sh path/to/schema.xml`** before **`create-solr-conf-configmap.sh`**.

### Docker Compose in this repo (coronawhy/solr)

**`docker cp solr:/var/solr/data/dataverse/conf`** usually yields **only `schema.xml`**, because **`docker-compose.yml`** bind-mounts **`./config/schema.xml`** onto that path and the rest of the core config may live elsewhere in the image. List keys on the cluster ConfigMap: **`kubectl get cm dataverse-besties-solr-conf -o json \| jq -r '.data \| keys \| length'`** — it should be **many**, not **`1`**.

Find **`solrconfig.xml`** inside the container, then copy **that directory** (or assemble a full `conf/` from the Dataverse release):

```bash
docker compose exec solr find /opt/solr /var/solr -name solrconfig.xml 2>/dev/null
# Example: if the path is /opt/solr/server/solr/configsets/foo/conf
docker cp "solr:/opt/solr/server/solr/configsets/foo/conf" ./dv-solr-conf
# Overlay repo schema if you customize it:
cp ./config/schema.xml ./dv-solr-conf/schema.xml
./ops/create-solr-conf-configmap.sh "$(pwd)/dv-solr-conf" demo-dataverse-besties
```

- Follow **[Dataverse Solr prerequisites](https://guides.dataverse.org/en/latest/installation/prerequisites.html#solr)** for your version.  
- Typical source: the **Dataverse release zip** / installer tree, or the **`conf/`** tree under the IQSS Dataverse Git repo for the Solr version you run (often under a path like `conf/solr/...` for a given Solr minor).

Your Solr image is **8.11.x** (Bitnami legacy); use the config that matches **Dataverse + Solr 8** for your release.

---

## 3. Kubernetes ConfigMap `dataverse-besties-solr-conf`

From the directory that contains `schema.xml`, `solrconfig.xml`, and any other files for that release (IQSS **v6.10.1** → use **`ops/fetch-dataverse-solr-conf.sh`** above):

```bash
chmod +x ops/create-solr-conf-configmap.sh
./ops/create-solr-conf-configmap.sh /absolute/path/to/solr/conf demo-dataverse-besties
```

Or manually:

```bash
kubectl create configmap dataverse-besties-solr-conf \
  --namespace=demo-dataverse-besties \
  --from-file=/absolute/path/to/solr/conf \
  --dry-run=client -o yaml | kubectl apply -f -
```

---

## 4. Solr HTTP basic auth (besties)

**Besties** bakes **`SOLR_ADMIN_USER`** / **`SOLR_ADMIN_PASSWORD`** into Helm values with **`envsubst`** (same GitHub Environment secrets as the main container’s Solr URL env vars). **`solrInit.adminUser`** / **`adminPassword`** use those placeholders; **`solrInit.existingSecret`** is empty, so no **`dataverse-solr-init-auth`** Secret is required.

For **other** environments, you can instead set **`solrInit.existingSecret`** to a cluster Secret name (keys **`SOLR_ADMIN_USER`**, **`SOLR_ADMIN_PASSWORD`**) and leave **`adminUser`** / **`adminPassword`** empty.

If Solr has **no** HTTP basic auth, use empty **`SOLR_ADMIN_*`** in CI and adjust Solr URL values in the tmpl (drop **`user:pass@`**) and set **`solrInit.adminUser`** / **`adminPassword`** to empty strings.

---

## 5. Deploy

Run your normal deploy (or `envsubst` + `helm upgrade`). Ensure **`DATAVERSE_SOLR_CORE`** matches your collection/core name (often **`dataverse`**).

---

## Troubleshooting

- **InitContainer fails on `solr zk`:** check **`solrInit.zkConnect`** in rendered values (chroot, DNS, port **2181**).  
- **401 from Solr:** fix GitHub **`SOLR_ADMIN_*`** / values (**`solrInit.adminUser`** / **`adminPassword`**) or **`existingSecret`** keys, or disable Solr auth.  
- **Collection CREATE returns HTTP 400:** the init script prints Solr’s JSON error body. Causes include: **`schema.xml` / Solr 8.11** — **`analyzer/tokenizer: missing mandatory attribute 'class'`** → run **`./ops/patch-dataverse-schema-solr811.sh`** on **`schema.xml`** and re-apply the ConfigMap. **ZK chroot** — Bitnami usually needs **`/solr`** on **`zkConnect`**. **Replicas** — try **`replicationFactor: 1`** if nodes are insufficient.  
- **Schema errors:** conf must match your **Dataverse** version.
