# Private Ollama access

Ollama should not be exposed directly to the public internet on port `11434`.
Start with loopback access, then use one controlled private path when another
device needs the API.

## Local-only service

```bash
sudo ./scripts/ollama/configure-service.sh
./scripts/ollama/health-check.sh
```

The default binds `127.0.0.1:11434` and applies the workstation values used for
long-running Forge tests:

- context length: `65536`
- parallel requests: `2`
- maximum queue: `64`
- keep alive: `24h`

## Private network access

Prefer a private overlay network such as Tailscale, an authenticated reverse
proxy, or binding Ollama to one specific private interface. Do not use
`0.0.0.0` unless you understand that every host interface will accept traffic;
the configuration script requires an explicit acknowledgement for it.

After changing the bind address, separately restrict the host firewall to the
trusted private network and test both endpoints:

```bash
./scripts/ollama/health-check.sh http://PRIVATE_ADDRESS:11434
```

Do not put bearer tokens, tunnel credentials, private DNS records, or production
Forge gateway settings in this repository.
