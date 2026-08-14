# Isolated Forge/Hermes runtime

Reusable helpers for running Hermes against a local Ollama service without
mixing its cache, configuration, profiles, or temporary files with the rest of
the user account.

The default endpoint is `http://127.0.0.1:11434`. The tools do not include
WhatsApp credentials, production phone numbers, customer transcripts, API
tokens, or Motion Foundry business data.

## Start an isolated command

```bash
./setups/forge-runtime/run-isolated.sh /path/to/forge-project -- hermes
```

The following directories are created inside the selected project:

```text
.runtime/hermes-home
.runtime/cache
.runtime/config
.runtime/share
.runtime/tmp
```

Add `.runtime/` to that project's `.gitignore`.

## Check the toolchain

```bash
./setups/forge-runtime/health-check.sh
```

This reports installed versions and checks both Ollama API shapes without
sending a prompt.

## Harden a public Hermes profile

Preview the changes first:

```bash
./setups/forge-runtime/harden-profile.sh mfda-leads
```

Apply them only after reviewing the output:

```bash
./setups/forge-runtime/harden-profile.sh mfda-leads --apply --restart
```

The hardening helper disables Hermes memory and user-profile features for the
selected profile and backs up its `SOUL.md` when found. Tool availability still
depends on the installed Hermes version, so test with synthetic data before
connecting a customer-facing gateway.
