# CLAUDE.md

## Security and hygiene rules (every agent session)

1. Never commit secrets: no API keys, tokens, passwords, private keys, or .env files. Templates belong in *.example files with placeholder values only.
2. Untracking or deleting a file does not remove it from git history. If a secret ever lands in a commit: rotate it at the provider first, then rewrite history with git filter-repo.
3. At the end of each session: delete unused code, merge duplicate helpers, remove commented-out blocks. Use deterministic tools (linters, dead-code finders) and review the diff before deleting.
4. Keep .gitignore covering .env, .env.*, and secrets.* (with !*.example exemptions). Never weaken it.
5. The gitleaks CI workflow (.github/workflows/gitleaks.yml) stays. Never remove or bypass it.
6. After editing any file, verify the edit by reading the changed content back out of the file before committing. Never rely on a proxy check (lint, generate, build) that would also pass on the unedited file. Structured files (plist, XML, JSON, YAML) are edited with structured tools only (PlistBuddy, plutil, a real parser), never with regex substitutions piped through nested shell or osascript quoting.
