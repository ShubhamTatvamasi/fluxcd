# fluxcd

https://fluxcd.io/flux/

Install Flux cli tool:
```bash
brew install fluxcd/tap/flux
```

Deploy Flux on a cluster: 
```bash
flux bootstrap
```


---

### Helm Setup - fluxcd-community

Install Flux Operator:
```bash
helm install flux-operator \
  oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
  --namespace flux-system \
  --create-namespace
```

