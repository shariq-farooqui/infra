# TLS strategy

Two certificate patterns coexist in the cluster.

## Public services: per-host certificates

Hosts served on the public internet (`farooqui.ai`, `www.farooqui.ai`,
`status.farooqui.ai`, `analytics.farooqui.ai`) own their TLS. Each
`Ingress` declares its own `spec.tls.secretName` and cert-manager
issues a dedicated Let's Encrypt certificate per host via the
`letsencrypt-prod` `ClusterIssuer` (DNS-01, Cloudflare). These
Ingresses also pin the `cloudflare-origin-pull` `TLSOption`, so
Traefik only completes the handshake for clients presenting the CF
Origin Pull CA client cert — direct-IP requests fail at TLS.

## Private services: shared wildcard, default TLSStore

Tailnet-only services (anything reachable via the `*.farooqui.ai`
Cloudflare wildcard pointing at the homelab's CGNAT tailnet IP)
share a single `*.farooqui.ai` + `farooqui.ai` wildcard certificate.
The wildcard lives in one Secret in the `traefik` namespace and is
served via Traefik's default `TLSStore`; private Ingresses declare
`tls.hosts` without a `secretName` and fall back to it.

### Why a wildcard rather than per-host certs

The decisive argument is **Certificate Transparency log hygiene**.
Every certificate Let's Encrypt issues is published to public CT
logs (crt.sh, merklemap, etc.) and is trivially scrapable. Issuing
per-host certs for `paperless.farooqui.ai`, `immich.farooqui.ai`,
`vaultwarden.farooqui.ai`, and so on would publish a hostname
inventory of the homelab to the entire internet, regardless of the
fact that those hosts resolve only to a tailnet address. A wildcard
leaks only the apex pattern; the set of services behind it stays
private.

Secondary benefits:

- **Smaller key-material surface.** One Secret, mounted into one
  Deployment (Traefik). No reflector fan-out, no per-namespace copies.
- **Fewer ACME calls.** A single DNS-01 challenge renews the whole
  private surface, leaving plenty of headroom against Let's Encrypt
  rate limits as more services come online.

### The tradeoff

Renewal is all-or-nothing: if cert-manager fails to renew the
wildcard for long enough, every private service becomes untrusted
simultaneously rather than degrading one at a time. This
single-point-of-expiry is the real downside.

Mitigation is observability. `PrometheusRule`s in
`infrastructure/configs/observability/cert-expiry-alerts.yaml` watch
every cert-manager `Certificate` and fire `warning` at 14 days
remaining and `critical` at 3 days, plus a `CertificateNotReady`
alert that catches issuance failures before expiry ever arrives.
Alertmanager is currently disabled (single operator, alerts are
visible in the Grafana Alerts pane); wire it to email/ntfy/Slack
when the homelab graduates past "one human on call".

### Blast radius if compromised

A leaked wildcard key impersonates every private host. This is no
worse than a leak in any per-service cert in the same cluster,
because Traefik is the TLS terminator for all of them and would hold
every key regardless. The wildcard concentrates the key in one
namespace rather than smearing copies across every app.

## Cert-manager version and issuer

- cert-manager `v1.16.x` from the Jetstack chart, CRDs installed
  inline with the release.
- `letsencrypt-prod` `ClusterIssuer` using DNS-01 against
  `farooqui.ai` via a scoped Cloudflare API token (Zone.DNS:Edit on
  the farooqui.ai zone only).
