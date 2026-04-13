# fluxcd

https://fluxcd.io/flux/

https://registry.terraform.io/providers/fluxcd/flux/latest/docs

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

---

## Flux Operator with Flux UI

https://github.com/controlplaneio-fluxcd/flux-operator

https://artifacthub.io/packages/helm/flux-operator/flux-operator

Install Flux Operator:
```bash
helm upgrade -i flux-operator \
  oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
  --namespace flux-system \
  --create-namespace
```

Setup `Fine-grained` personal access tokens:
```
export GITHUB_TOKEN=<gh-token>
```
> Read and write `Contents`

Create git repo secret fof flux:
```bash
flux create secret git flux-system \
  --url=https://github.com/ShubhamTatvamasi/fluxcd.git \
  --username=git \
  --password=$GITHUB_TOKEN
```

Create a FluxInstance resource:
```yaml
kubectl apply -f - << EOF
apiVersion: fluxcd.controlplane.io/v1
kind: FluxInstance
metadata:
  name: flux
  namespace: flux-system
  annotations:
    fluxcd.controlplane.io/reconcileEvery: "1h"
    fluxcd.controlplane.io/reconcileArtifactEvery: "10m"
    fluxcd.controlplane.io/reconcileTimeout: "5m"
spec:
  sync:
    kind: GitRepository
    url: "https://github.com/ShubhamTatvamasi/fluxcd.git"
    ref: "refs/heads/main"
    path: "clusters/production"
    pullSecret: "flux-system"
    interval: 10m
  distribution:
    version: "2.x"
    registry: "ghcr.io/fluxcd"
    artifact: "oci://ghcr.io/controlplaneio-fluxcd/flux-operator-manifests"
  components:
    - source-controller
    - kustomize-controller
    - helm-controller
    - notification-controller
    - image-reflector-controller
    - image-automation-controller
  cluster:
    type: kubernetes
    size: medium
    multitenant: false
    networkPolicy: true
    domain: "cluster.local"
  kustomize:
    patches:
      - target:
          kind: Deployment
        patch: |
          - op: replace
            path: /spec/template/spec/nodeSelector
            value:
              kubernetes.io/os: linux
          - op: add
            path: /spec/template/spec/tolerations
            value:
              - key: "CriticalAddonsOnly"
                operator: "Exists"
EOF
```

http://localhost:9080/

Access the Flux Web UI:
```bash
kubectl -n flux-system port-forward svc/flux-operator 9080:9080
```


---


Delete Airflow:
```bash
kubectl -n flux-system delete \
  kustomization/airflow \
  kustomization/postgres \
  kustomization/airflow-base
```
