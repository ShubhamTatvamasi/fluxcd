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

flux reconcile if you don't want to wait: 
```bash
flux reconcile kustomization infrastructure
```

---

### Helm Setup

Install Flux Operator:
```bash
helm install flux-operator \
  oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
  --namespace flux-system \
  --create-namespace
```
> This helm chart is maintained and released by the fluxcd-community on a best effort basis.


