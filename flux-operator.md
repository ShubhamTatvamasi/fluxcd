# flux-operator

https://github.com/controlplaneio-fluxcd/flux-operator \
https://artifacthub.io/packages/helm/flux-operator/flux-operator


Install Flux Operator:
```bash
helm upgrade -i flux-operator \
  oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
  --namespace flux-system \
  --create-namespace
```

Create a FluxInstance components:
```yaml
kubectl apply -f - << EOF
apiVersion: fluxcd.controlplane.io/v1
kind: FluxInstance
metadata:
  name: flux
  namespace: flux-system
  annotations:
    fluxcd.controlplane.io/reconcile: "enabled"
    fluxcd.controlplane.io/reconcileEvery: "1h"
    fluxcd.controlplane.io/reconcileTimeout: "5m"
spec:
  distribution:
    version: "2.x"
    registry: "ghcr.io/fluxcd"
  components:
    - source-controller
    - kustomize-controller
    - helm-controller
    - notification-controller
    - image-reflector-controller
    - image-automation-controller
    - source-watcher
  cluster:
    type: kubernetes
    size: medium
    multitenant: false
    networkPolicy: true
    domain: "cluster.local"
  commonMetadata:
    labels:
      app.kubernetes.io/name: flux
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

Setup your git repo:
```yaml
kubectl apply -f - << EOF
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: flux-system
  namespace: flux-system
spec:
  interval: 5m0s
  url: https://github.com/ShubhamTatvamasi/fluxcd.git
  ref:
    branch: main
EOF
```

Sync your cluster:
```yaml
kubectl apply -f - << EOF
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: flux-system
  namespace: flux-system
spec:
  force: false
  interval: 10m0s
  path: clusters/rke2
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
EOF
```

Upgrade Flux Operator with Web UI and Ingress:
```bash
helm upgrade -i flux-operator \
  oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
  --namespace flux-system \
  --create-namespace \
  --set "web.ingress.enabled=true" \
  --set "web.ingress.hosts[0].host=flux.k8s.shubhamtatvamasi.com" \
  --set "web.ingress.hosts[0].paths[0].path=/" \
  --set "web.ingress.hosts[0].paths[0].pathType=ImplementationSpecific" \
  --set "web.ingress.tls[0].secretName=flux-tls" \
  --set "web.ingress.tls[0].hosts[0]=flux.k8s.shubhamtatvamasi.com" \
  --set web.config.baseURL=https://flux.k8s.shubhamtatvamasi.com \
  --set web.config.authentication.type=OAuth2 \
  --set web.config.authentication.oauth2.provider=OIDC \
  --set web.config.authentication.oauth2.clientID=flux-web-ui \
  --set web.config.authentication.oauth2.clientSecret=flux-dex-client-secret \
  --set web.config.authentication.oauth2.issuerURL=https://dex.k8s.shubhamtatvamasi.com
```

---

### Extra


http://localhost:9080/

Access the Flux Web UI:
```bash
kubectl -n flux-system port-forward svc/flux-operator 9080:9080
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

Delete Airflow:
```bash
kubectl -n flux-system delete \
  kustomization/airflow \
  kustomization/postgres \
  kustomization/airflow-base
```
