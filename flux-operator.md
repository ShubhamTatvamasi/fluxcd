# flux-operator


```bash
helm upgrade -i flux-operator \
  oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
  --namespace flux-system \
  --create-namespace \
  --set ingress.enabled=true \
  --set "ingress.hosts[0].host=fluxcd.k8s.shubhamtatvamasi.com" \
  --set "ingress.hosts[0].paths[0].path=/" \
  --set "ingress.hosts[0].paths[0].pathType=Prefix" \
  --set "ingress.tls[0].secretName=shubhamtatvamasi-tls" \
  --set "ingress.tls[0].hosts[0]=fluxcd.k8s.shubhamtatvamasi.com" \
  --wait
```
