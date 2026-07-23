# SOPS

Install sops and age:
```bash
brew install sops age
```

Generate an Age key pair:
```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/age.agekey
```

Create a Kubernetes secret with the Age private key:
```bash
kubectl create secret generic sops-age \
  -n flux-system \
  --from-file=age.agekey=$HOME/.config/sops/age/age.agekey
```

Verify the secret was created successfully:
```bash
kubectl get secret -n flux-system sops-age -o yaml | \
  yq '.data |= with_entries(.value |= @base64d)'
```

Encrypt a file with sops:
```bash
sops --encrypt secret.yaml
```
