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
