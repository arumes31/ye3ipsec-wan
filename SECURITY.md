# Security Policy

## Reporting a vulnerability

Report suspected vulnerabilities privately through GitHub Security Advisories.
Do not include VPN credentials, private keys, packet captures, or production
configuration in a public issue.

## Credential handling

Runtime logs redact credentials. Generated primary credentials are stored under
`/etc/swanctl/ye3ipsec-wan/credential` with directory mode `0700` and file mode
`0600`. Multi-user secrets and private keys are likewise restricted under
`/etc/swanctl/conf.d` and `/etc/swanctl/private`.

Anyone with access to the container runtime socket or the persistent swanctl
volume can read these secrets and must be treated as a privileged administrator.
Retrieve only the required file through an interactive exec session and never
copy credential output into CI or centralized logs.

Images predating version 1.1.8 could print credentials when `Y_SHOW_CRED=yes`
(the former default). Review retained runtime logs and rotate every value that
may have been captured before upgrading.

## Deployment protection

The publish workflow targets the `ghcr-production` GitHub environment. Configure
that environment to allow only the default branch and require a reviewer before
manual deployments. Published images include SBOM and provenance attestations.
