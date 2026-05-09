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
  --wait
```
