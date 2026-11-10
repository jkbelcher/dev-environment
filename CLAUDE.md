# Dev Environment

Config files and setup scripts for a macOS dev machine. See `README.md` for what each directory holds and where it gets installed.

## This repo is public

Treat everything committed here as published to the world, history included.

- **Never commit secrets:** API keys, tokens, passwords, SSH/GPG keys, certificates, `.env` files, cloud credentials, license keys, cookies, or session data.
- **Never commit personal info:** email addresses, phone numbers, street addresses, device serial numbers, hostnames, Wi-Fi names, or account IDs.
- **No hardcoded home paths.** Use `~` or `$HOME`, not `/Users/<name>/`.
- **Check configs copied from the machine.** App configs (and backups like `tmux/backup_tmux.sh`) can pick up tokens, account emails, or recent-file paths. Read the diff before committing.
- **Secrets stay outside the repo.** If a config needs one, load it at runtime from an untracked file (e.g. `~/.config/<tool>/secrets`) or the macOS Keychain, and note that in the README.
- **Review before every commit:** run `git diff --cached` and look for any of the above.
- **If something sensitive is already committed, stop and tell the user.** A new commit doesn't remove it; it needs a history rewrite, and the secret needs rotating.

## Conventions

- One top-level directory per tool. Add a row to the README table when adding one, and keep the README's Setup section in sync with any new install steps.
- Scripts start with a shebang and a short header comment, and resolve paths from the script's own directory or `$HOME`.
