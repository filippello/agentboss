# Homebrew tap for FocusPal

This directory holds the Cask formula for distributing FocusPal via Homebrew.

The formula itself can't live here — Homebrew requires it to be in a repo named `homebrew-tap` on the same GitHub account. So treat this folder as a **template** that you copy into the tap repo on every release.

## One-time setup

1. Create a new public GitHub repo named **`homebrew-tap`** under your account (e.g. `https://github.com/filippello/homebrew-tap`).
2. Copy `Casks/focuspal.rb` from this folder into the new repo at `Casks/focuspal.rb`.
3. Commit + push to the tap repo's `main` branch.

That's it. Users can then run:

```bash
brew tap filippello/tap            # adds the tap
brew install --cask focuspal       # installs FocusPal.app to /Applications
```

(Or in one shot: `brew install --cask filippello/tap/focuspal`.)

## Releasing a new version

When you cut a new release here:

1. `git tag vX.Y.Z && git push --tags` — the GitHub Actions workflow builds, zips, and publishes the release with a `.sha256` file.
2. Wait for the workflow to finish, then grab the SHA-256:
   ```bash
   curl -sL "https://github.com/filippello/agentboss/releases/download/vX.Y.Z/FocusPal-vX.Y.Z-arm64.zip.sha256" | awk '{print $1}'
   ```
3. Update `Casks/focuspal.rb` here:
   - bump `version "X.Y.Z"`
   - replace the `sha256 "..."` value
4. Copy the updated file to the `homebrew-tap` repo and push.
5. Users update with `brew upgrade --cask focuspal`.

## Why isn't the tap automated?

It could be — a GitHub Actions step on this repo could `git push` an updated formula to the tap repo using a personal access token. Out of scope for v0.2; the manual update is two minutes of work and avoids needing to manage a long-lived token. Add it later if the release cadence picks up.

## Notes about the unsigned binary

The bundle isn't code-signed (no Apple Developer ID). Homebrew installs the `.app` to `/Applications` regardless, but on first launch macOS Gatekeeper will block it. The user has to right-click `FocusPal.app` → **Open** → confirm. The Cask formula can't bypass that without a Developer ID.
