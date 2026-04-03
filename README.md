# fluxcd

https://fluxcd.io/flux/

Install `flux` cli tool:
```bash
brew install fluxcd/tap/flux
```

Check prerequisites before installing flux:
```bash
flux check --pre
```

Setup Fine-grained personal access tokens:
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
  --path=clusters/shubham \
  --personal
```
> remove `--personal` flag if deploying for org,
> add `--hostname` if using for GitHub Enterprise

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


