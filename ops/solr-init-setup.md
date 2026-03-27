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

### Why Docker Compose works but **`solrInit`** needs a fatter directory

In **this repo’s Compose** setup, **`coronawhy/solr`** already has a **full core layout** on disk inside the image (and under the named volume): **`solrconfig.xml`**, **`lang/`**, **`stopwords.txt`**, etc. You only **bind-mount `./config/schema.xml`** over the core’s schema, so Solr still loads every other file from the image.

**Kubernetes `solrInit`** does **not** use that layout. It builds a **configset from a ConfigMap** and runs **`solr zk upconfig`**. ZooKeeper (and every Solr node) only see **what you uploaded** — so **`stopwords.txt`**, **`lang/stopwords_en.txt`**, and every other path referenced in **`schema.xml`** must **exist in the ConfigMap**. IQSS only checks **three** files into Git (`schema.xml`, `solrconfig.xml`, `update-fields.sh`); the rest normally lives in Solr’s stock **`_default`** configset. **`ops/fetch-dataverse-solr-conf.sh`** therefore downloads IQSS + **merges** **`lang/`** and the root **`*.txt`** helpers from **`apache/lucene-solr`** tag **`releases/lucene-solr/8.11.2`** (aligned with Bitnami Solr **8.11.x**), then applies the Solr **8.11** schema patch.

You need the **official** Solr files for your Dataverse version: **`solrconfig.xml`** and **`schema.xml`**, **plus** those merged helpers for K8s.

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

**Solr 8.11 (Bitnami):** **`fetch-dataverse-solr-conf.sh`** runs **`ops/merge-solr811-default-resources.sh`** ( **`lang/`**, **`stopwords.txt`**, … from **`apache/lucene-solr`** tag **`releases/lucene-solr/8.11.2`**) and **`ops/patch-dataverse-schema-solr811.sh`** (legacy **`<tokenizer name="..."/>`** → **`class=`**). If you assemble **`dv-solr-conf`** by hand, run **merge + patch** before **`create-solr-conf-configmap.sh`**.

**Verify the bundle:** after fetch, **`dv-solr-conf/`** should include **`solrconfig.xml`**, **`schema.xml`**, **`stopwords.txt`**, and a **`lang/`** directory (dozens of files total). A ConfigMap built from only IQSS’s three Git files will fail in the cluster (**missing `stopwords.txt`**, **`tokenizer` `class`**, etc.).

**Local Compose vs cluster Solr version:** **`docker-compose.yml`** uses **`coronawhy/solr:8.9.0`**; **besties** uses **Bitnami Solr 8.11.x**. The same IQSS **`schema.xml` / `solrconfig.xml`** plus merged **`_default`** resources are intended to work for both; bump the Compose image toward **8.11** if you need tighter parity.

**`config/schema.xml` in this repo:** default Compose only bind-mounts that file; the image supplies **`solrconfig.xml`**, **`lang/`**, etc. For **`solrInit`**, use **`fetch-dataverse-solr-conf.sh`** (add **`OVERLAY_REPO_SCHEMA=1`** to bake **`./config/schema.xml`** into **`dv-solr-conf/schema.xml`**). To drive local Solr from the **same tree** as the ConfigMap, replace the Compose volume with **`./dv-solr-conf:/var/solr/data/dataverse/conf:ro`** (and drop the **`config/schema.xml`** line), or keep schema-only dev and refresh **`./config/schema.xml`** from **`dv-solr-conf/schema.xml`** when you cut a new cluster bundle.

See **[Dataverse Solr prerequisites](https://guides.dataverse.org/en/latest/installation/prerequisites.html#solr)** for version notes and the release zip if you are not using the fetch script.

---

## 3. Kubernetes ConfigMap `dataverse-besties-solr-conf`

Point at the **full** directory produced by **`fetch-dataverse-solr-conf.sh`** (typically **`dv-solr-conf/`** — gitignored). **`kubectl create configmap --from-file=`** turns each file into a ConfigMap data key (including **`lang/stopwords_en.txt`**-style paths when present).

```bash
chmod +x ops/create-solr-conf-configmap.sh
./ops/create-solr-conf-configmap.sh "$(pwd)/dv-solr-conf" demo-dataverse-besties
```

Or manually:

```bash
kubectl create configmap dataverse-besties-solr-conf \
  --namespace=demo-dataverse-besties \
  --from-file=/absolute/path/to/dv-solr-conf \
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
- **Collection CREATE returns HTTP 400:** the init script prints Solr’s JSON error body. **`Can't find resource 'stopwords.txt'`** (or other **`lang/`** files) → re-run **`./ops/fetch-dataverse-solr-conf.sh`** (or **`./ops/merge-solr811-default-resources.sh "$(pwd)/dv-solr-conf"`**) and re-apply the ConfigMap. **`analyzer/tokenizer: missing mandatory attribute 'class'`** → run **`./ops/patch-dataverse-schema-solr811.sh`** on **`schema.xml`**. **ZK chroot** — Bitnami usually needs **`/solr`** on **`zkConnect`**. **Replicas** — try **`replicationFactor: 1`** if nodes are insufficient.  
- **Schema errors:** conf must match your **Dataverse** version.
