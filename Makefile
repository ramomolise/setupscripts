SHELL := /bin/bash

.PHONY: check syntax secrets

check: syntax secrets
	@if command -v shellcheck >/dev/null 2>&1; then \
		find . -type f -name '*.sh' -not -path './.git/*' -print0 | \
			xargs -0 shellcheck --external-sources; \
	else \
		echo 'shellcheck not installed; skipped lint'; \
	fi
	@python3 -m py_compile setups/debian-qtile/config/qtile/config.py
	@git diff --check

syntax:
	@find . -type f -name '*.sh' -not -path './.git/*' -print0 | \
		xargs -0 -n1 bash -n

secrets:
	@bash scripts/check-secrets.sh
