# infra

[![validate](https://github.com/shariq-farooqui/infra/actions/workflows/validate.yaml/badge.svg)](https://github.com/shariq-farooqui/infra/actions/workflows/validate.yaml)
[![lint](https://github.com/shariq-farooqui/infra/actions/workflows/lint.yaml/badge.svg)](https://github.com/shariq-farooqui/infra/actions/workflows/lint.yaml)
[![licence](https://img.shields.io/github/license/shariq-farooqui/infra?color=blue)](LICENSE)

Declarative infrastructure for my single-node homelab. A Hetzner server running NixOS + k3s, reconciled from this repo by Flux. Public site at [farooqui.ai](https://farooqui.ai), status page at [status.farooqui.ai](https://status.farooqui.ai), tailnet-only Grafana for metrics and logs, restic snapshots to Cloudflare R2.

## Layout

```
nixos/              NixOS flake for the host: disko, k3s, Tailscale, restic
opentofu/           GitHub branch protection, Cloudflare DNS, AOP, R2
clusters/homelab/   Flux entry point: GitRepository + root Kustomization
infrastructure/     cluster-side tools
  controllers/      HelmReleases and the Secrets they consume
  configs/          Ingresses, ClusterIssuers, TLSOptions, runtime config
apps/               user-facing workloads (personal-site, gatus)
```

## Toolchain

- **NixOS** on the host; disko does the btrfs layout.
- **k3s** as the Kubernetes distribution, Traefik disabled so a Flux HelmRelease owns the ingress.
- **Flux** pulls this repo over HTTPS every minute.
- **OpenTofu** for GitHub branch protection and Cloudflare resources, auth via a GitHub App.
- **sops-nix** and **SOPS-in-Flux** for secrets, separate age keypairs for host and cluster.
- **Tailscale** for admin SSH and for private services. Grafana runs on it now; family-shared apps can follow the same pattern.
- **Renovate** watches chart and Action versions; **flux-local** renders every manifest offline in CI.

## Licence

[MIT](LICENSE).
