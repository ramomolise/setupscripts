# Security

These scripts can install packages, change services, and modify storage. Read a
script before running it and use a test machine when possible.

## Reporting a problem

Open a GitHub issue for a safety bug that does not expose a real credential. If
the report includes a token, password, customer detail, private address, or
other sensitive value, contact the repository owner privately instead.

## Repository rules

- No passwords, API keys, tokens, customer data, or production gateway URLs.
- Destructive tools must validate their target and require explicit consent.
- Downloaded installers must use HTTPS and an official upstream source.
- Hardware-specific changes should begin with read-only diagnostics.
