# flux-operator


```bash
helm upgrade -i flux-operator \
  oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
  --namespace flux-system \
  --create-namespace \
  --set "web.ingress.enabled=true" \
  --set "web.ingress.hosts[0].host=fluxcd.k8s.shubhamtatvamasi.com" \
  --set "web.ingress.hosts[0].paths[0].path=/" \
  --set "web.ingress.hosts[0].paths[0].pathType=ImplementationSpecific" \
  --set "web.ingress.tls[0].secretName=shubhamtatvamasi-tls" \
  --set "web.ingress.tls[0].hosts[0]=fluxcd.k8s.shubhamtatvamasi.com" \
  --set web.config.baseURL=https://fluxcd.k8s.shubhamtatvamasi.com \
  --set web.config.authentication.type=OAuth2 \
  --set web.config.authentication.oauth2.provider=OIDC \
  --set web.config.authentication.oauth2.clientID=flux-web-ui \
  --set web.config.authentication.oauth2.clientSecret=flux-dex-client-secret \
  --set web.config.authentication.oauth2.issuerURL=https://dex.k8s.shubhamtatvamasi.com \
  --wait
```

---

## Flux Operator with Flux UI

https://github.com/controlplaneio-fluxcd/flux-operator \
https://artifacthub.io/packages/helm/flux-operator/flux-operator

Install Flux Operator:
```bash
helm upgrade -i flux-operator \
  oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
  --namespace flux-system \
  --create-namespace \
  --wait
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
    - source-watcher
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

