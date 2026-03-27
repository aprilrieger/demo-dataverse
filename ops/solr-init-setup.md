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

---

## 2. Solr `conf/` directory (Dataverse release)

You need the **full** Solr configuration directory for your Dataverse version (not only `schema.xml`).

- Follow **[Dataverse Solr prerequisites](https://guides.dataverse.org/en/latest/installation/prerequisites.html#solr)** for your version.  
- Typical source: the **Dataverse release zip** / installer tree, or the **`conf/`** tree under the IQSS Dataverse Git repo for the Solr version you run (often under a path like `conf/solr/...` for a given Solr minor).

Your Solr image is **8.11.x** (Bitnami legacy); use the config that matches **Dataverse + Solr 8** for your release.

---

## 3. Kubernetes ConfigMap `dataverse-besties-solr-conf`

From the directory that contains `schema.xml`, `solrconfig.xml`, and the rest of `conf/`:

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

## 4. Secret for Solr HTTP basic auth (initContainer)

If Bitnami Solr has **`SOLR_ENABLE_AUTHENTICATION=yes`**, the init job must call Solr with the same user/password. Create a Secret **in the Dataverse namespace** with keys **`SOLR_ADMIN_USER`** and **`SOLR_ADMIN_PASSWORD`** (match **`solrInit.existingSecret`** in values, default **`dataverse-solr-init-auth`**):

```bash
kubectl create secret generic dataverse-solr-init-auth \
  --namespace=demo-dataverse-besties \
  --from-literal=SOLR_ADMIN_USER='your-solr-admin-user' \
  --from-literal=SOLR_ADMIN_PASSWORD='your-solr-admin-password'
```

Use the **same** credentials you already put in GitHub **`SOLR_ADMIN_USER`** / **`SOLR_ADMIN_PASSWORD`** for Dataverse env (init runs in-cluster and does not see GitHub secrets).

If Solr has **no** HTTP basic auth, set **`solrInit.existingSecret: ""`** in **`ops/besties-deploy.tmpl.yaml`** (or your values overlay) and remove or ignore this Secret.

---

## 5. Deploy

Run your normal deploy (or `envsubst` + `helm upgrade`). Ensure **`DATAVERSE_SOLR_CORE`** matches your collection/core name (often **`dataverse`**).

---

## Troubleshooting

- **InitContainer fails on `solr zk`:** check **`solrInit.zkConnect`** in rendered values (chroot, DNS, port **2181**).  
- **401 from Solr:** fix Secret keys / Bitnami **`SOLR_ADMIN_*`** or disable Solr auth and clear **`existingSecret`**.  
- **Collection create fails:** confirm enough Solr nodes for **`replicationFactor`** (e.g. 2 replicas need 2 Solr pods).  
- **Schema errors:** conf must match your **Dataverse** version.
