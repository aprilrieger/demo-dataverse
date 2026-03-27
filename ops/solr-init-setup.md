# Solr init (`solrInit`)

**Besties** (`ops/besties-deploy.tmpl.yaml`) has **`solrInit.enabled: true`**. The chart runs a **pre-start initContainer** that:

1. Waits for Solr’s HTTP API  
2. Runs **`solr zk upconfig`** to load a **Dataverse** configset into **ZooKeeper**  
3. Creates the **`dataverse`** collection if it does not exist (shards / replicas from Helm values)

Other environments can turn the same behavior on in **`charts/demo-dataverse/values.yaml`** or a values overlay.

For **besties**, **`solrInit.zkConnect`** is set **in git** in **`ops/besties-deploy.tmpl.yaml`** (same string your Solr nodes use). Edit that value when ZK hostnames or chroot change; the deploy workflow does **not** use a **`ZK_CONNECT`** secret.

### Dataverse search + Solr HTTP basic auth (stock `gdcc/dataverse` image)

Dataverse’s **`SolrClientService`** builds SolrJ’s **`Http2SolrClient`** as **`new Http2SolrClient.Builder(getSolrUrl()).build()`** with **no** **`withBasicAuthCredentials(...)`** (IQSS source: `SolrClientService.java` / `AbstractSolrClientService.getSolrUrl()`). In SolrJ **9.x**, **`Authorization: Basic …`** is **not** derived from **`user:password@host`** in the URL string; credentials must be set on the builder (see Apache **`HttpSolrClientBuilderBase#withBasicAuthCredentials`** and **SOLR-15154**). So **Helm env vars** such as **`DATAVERSE_SOLR_HOST=user:pass@solr…`**, **`dataverse_solr_host`**, or **`:SolrHostColonPort`** containing **`user:pass@…`** **do not** make search/index calls authenticate to Solr — you still see **`http://solr…:8983/solr/...`** and **401** in logs.

**Practical options:**

1. **Turn off Solr HTTP auth** for a **private cluster** Solr that is only reachable inside the mesh (common for demos). **Bitnami Solr** chart: set **`auth.enabled: false`** (see upstream **`bitnami/solr`** `values.yaml`). Then point Dataverse at **`solr.solr.svc.cluster.local`** with **no** **`user:pass@`** in host env vars; **`solrInit`** can use empty **`SOLR_ADMIN_*`** (its script skips **`-u`** when unset).
2. **Custom Dataverse image / upstream patch:** extend IQSS **`SolrClientService`** to call **`withBasicAuthCredentials(user, pass)`** using new MicroProfile keys (host must be **hostname only**, credentials separate).
3. **Do not rely on** putting passwords only in **`DATAVERSE_SOLR_HOST`** for fixing **401** on **`/select`** — that path will not work with the stock container.

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

**Solr 8.11 (Bitnami):** IQSS **`solrconfig.xml`** for recent Dataverse tracks **Solr 9** (**`luceneMatchVersion` 9.x** and **`solr.NumFieldLimitingUpdateRequestProcessorFactory`**). That class does **not** exist on Solr **8.11.x**, so collection CREATE fails with **`Caused by: solr.NumFieldLimitingUpdateRequestProcessorFactory`**. **`fetch-dataverse-solr-conf.sh`** therefore runs **`ops/patch-dataverse-solrconfig-solr811.sh`** (removes that URP, sets **`luceneMatchVersion`** to **8.11.2**), plus **`ops/merge-solr811-default-resources.sh`** ( **`lang/`**, **`stopwords.txt`**, …) and **`ops/patch-dataverse-schema-solr811.sh`** ( **`<tokenizer name="..."/>`** → **`class=`**). If you assemble **`dv-solr-conf`** by hand, run **merge + both patches** before **`create-solr-conf-configmap.sh`**.

**Verify the bundle:** after fetch, **`dv-solr-conf/`** should include **`solrconfig.xml`**, **`schema.xml`**, **`stopwords.txt`**, and a **`lang/`** directory (dozens of files total). A ConfigMap built from only IQSS’s three Git files will fail in the cluster (**missing `stopwords.txt`**, **`tokenizer` `class`**, etc.).

**Local Compose vs cluster Solr version:** **`docker-compose.yml`** uses **`coronawhy/solr:8.9.0`**; **besties** uses **Bitnami Solr 8.11.x**. The same IQSS **`schema.xml` / `solrconfig.xml`** plus merged **`_default`** resources are intended to work for both; bump the Compose image toward **8.11** if you need tighter parity.

**`config/schema.xml` in this repo:** default Compose only bind-mounts that file; the image supplies **`solrconfig.xml`**, **`lang/`**, etc. For **`solrInit`**, use **`fetch-dataverse-solr-conf.sh`** (add **`OVERLAY_REPO_SCHEMA=1`** to bake **`./config/schema.xml`** into **`dv-solr-conf/schema.xml`**). To drive local Solr from the **same tree** as the ConfigMap, replace the Compose volume with **`./dv-solr-conf:/var/solr/data/dataverse/conf:ro`** (and drop the **`config/schema.xml`** line), or keep schema-only dev and refresh **`./config/schema.xml`** from **`dv-solr-conf/schema.xml`** when you cut a new cluster bundle.

See **[Dataverse Solr prerequisites](https://guides.dataverse.org/en/latest/installation/prerequisites.html#solr)** for version notes and the release zip if you are not using the fetch script.

---

## 3. Kubernetes ConfigMap `dataverse-besties-solr-conf`

Point at the **full** directory produced by **`fetch-dataverse-solr-conf.sh`** (typically **`dv-solr-conf/`** — gitignored).

**Important:** **`kubectl create configmap --from-file=/path/to/dir`** only adds **top-level** files in that directory; it **does not recurse** into **`lang/`** (and other subdirs), so Solr will fail with **`Can't find resource 'lang/stopwords_en.txt'`**. **`create-solr-conf-configmap.sh`** therefore packs the whole tree as **`solr-conf.tgz`** (single ConfigMap key, **`binaryData`**) and the Helm **`solr-init`** script untars it before **`zk upconfig`**.

```bash
chmod +x ops/create-solr-conf-configmap.sh
./ops/create-solr-conf-configmap.sh "$(pwd)/dv-solr-conf" demo-dataverse-besties
```

Or manually (equivalent tarball):

```bash
( cd /absolute/path/to/dv-solr-conf && COPYFILE_DISABLE=1 tar czf /tmp/solr-conf.tgz . )
kubectl create configmap dataverse-besties-solr-conf \
  --namespace=demo-dataverse-besties \
  --from-file=solr-conf.tgz=/tmp/solr-conf.tgz \
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
- **401 from Solr on search/index (`require authentication`, log URL is `http://solr…:8983/...` without credentials):** with the **stock** Dataverse image, SolrJ’s **`Http2SolrClient` never sends Basic Auth** unless the application calls **`withBasicAuthCredentials`** — embedding **`user:pass@`** in **`DATAVERSE_SOLR_HOST`** or **`:SolrHostColonPort`** does **not** fix this. See the callout **“Dataverse search + Solr HTTP basic auth”** above: use **`auth.enabled: false`** on **Bitnami Solr** (or equivalent) for internal-only Solr, or patch Dataverse / use a custom image. **`:SolrHostColonPort` in the DB** can still override host/port for URL construction but **cannot** add working SolrJ Basic Auth by itself.  
- **401 only from `solrInit` curl** (initContainer logs): that path **does** use **`SOLR_ADMIN_*`** with **`-u`** — fix GitHub secrets / **`solrInit.adminUser`** / **`adminPassword`**, or disable Solr auth as above.  
- **Collection CREATE returns HTTP 400:** the init script prints Solr’s JSON error body. **`Can't find resource 'stopwords.txt'`** or **`lang/stopwords_en.txt`** → if you built the ConfigMap with **`kubectl --from-file=dv-solr-conf`**, rebuild with **`./ops/create-solr-conf-configmap.sh`** (tarball). Otherwise re-run **`./ops/fetch-dataverse-solr-conf.sh`** (or **`./ops/merge-solr811-default-resources.sh "$(pwd)/dv-solr-conf"`**) and re-apply the ConfigMap. **`analyzer/tokenizer: missing mandatory attribute 'class'`** → run **`./ops/patch-dataverse-schema-solr811.sh`** on **`schema.xml`**. **`NumFieldLimitingUpdateRequestProcessorFactory`** on **Solr 8.11** → IQSS **`solrconfig.xml`** is Solr **9**-oriented; run **`./ops/patch-dataverse-solrconfig-solr811.sh "$(pwd)/dv-solr-conf/solrconfig.xml"`**, rebuild the ConfigMap, re-upload (or bump **`configSetName`** if ZK still has the old configset). **ZK chroot** — Bitnami usually needs **`/solr`** on **`zkConnect`**. **Replicas** — try **`replicationFactor: 1`** if nodes are insufficient. If a broken **`dataverse`** collection was created with a bad configset, delete it in Solr (or use a new **`configSetName`**) after fixing ZK.  
- **Schema errors:** conf must match your **Dataverse** version.
