# fluxcd

https://fluxcd.io/flux/ \
https://registry.terraform.io/providers/fluxcd/flux/latest/docs

https://fluxcd.io/resources/

Install `flux` cli tool:
```bash
brew install fluxcd/tap/flux
```

Check prerequisites before installing flux:
```bash
flux check --pre
```

Setup `Fine-grained` personal access tokens:
```
export GITHUB_TOKEN=<gh-token>
```
> Read and write `Contents`

Deploy Flux on a cluster: 
```bash
flux bootstrap github \
  --token-auth \
  --owner=ShubhamTatvamasi \
  --repository=fluxcd \
  --branch=main \
  --path=clusters/production \
  --personal
```
> remove `--personal` flag if deploying for org,
> add `--hostname` if using for GitHub Enterprise

Check flux installation after bootstrap:
```bash
flux check
```

---

Get list of deployed kustomizations:
```bash
kubectl get kustomization -A
```
```
NAMESPACE     NAME             AGE     READY   STATUS
flux-system   apps             7m19s   True    Applied revision: main@sha1:d641dd40b288515663bc1fb682f4780d7372849a
flux-system   flux-system      7m42s   True    Applied revision: main@sha1:d641dd40b288515663bc1fb682f4780d7372849a
flux-system   infrastructure   7m19s   True    Applied revision: main@sha1:d641dd40b288515663bc1fb682f4780d7372849a
```

reconcile flux-system kustomization:
```bash
flux -n flux-system \
  reconcile \
  kustomization flux-system
```

flux reconcile `infrastructure` if you have made any changes: 
```bash
flux -n flux-system \
  reconcile \
  kustomization infrastructure
```

---

reconcile helm chart:
```bash
flux -n prometheus \
  reconcile \
  source chart prometheus
```

---

Suspend a kustomization:
```bash
flux suspend kustomization airflow -n airflow
```

Resume a kustomization:
```bash
flux resume kustomization airflow -n airflow
```

---

Delete airflow:
```bash
kubectl -n airflow \
  delete kustomization airflow

kubectl -n airflow \
  delete kustomization postgres
```

Force update (touch the ResourceSet):
```bash
kubectl -n airflow \
  annotate resourceset airflow \
  reconcile.fluxcd.io/requestedAt="$(date +%s)" \
  --overwrite
```

---

Check Flux git repos:
```bash
kubectl get gitrepositories -A
```
```
NAMESPACE     NAME          URL                                              AGE   READY   STATUS
flux-system   flux-system   https://github.com/ShubhamTatvamasi/fluxcd.git   10h   True    stored artifact for revision 'refs/heads/main@sha1:87f175aa442c111dfd7334166565a4af9512baa5'
```

Fetch the latest code from git repo:
```bash
flux -n flux-system \
  reconcile \
  source git flux-system
```

---

Check all Resource Sets:
```bash
kubectl get resourcesets -A
```
