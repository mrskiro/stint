---
name: release
description: Run the stint release process. Determines version, generates release notes from commits, triggers the GitHub Actions build/sign/notarize workflow, and updates the release body. Use when the user says "release", "リリース", "バージョン上げて", "v0.x.0出して", or discusses shipping a new version.
---

# Release

Ship a new version of stint. Build, signing, notarization, and DMG creation are handled by GitHub Actions — this skill manages everything before and after.

## Prerequisites

- On `main` branch

If not on main, explain and stop.

## Steps

### 1. Verify state

```bash
git branch --show-current   # must be "main"
```

### 2. Determine version

Get the latest tag:

```bash
git describe --tags --abbrev=0
```

Ask the user: "Current version is vX.Y.Z. What's next? (patch / minor / major / explicit)"

- patch: X.Y.Z+1
- minor: X.Y+1.0
- major: X+1.0.0
- explicit: use the user's input as-is

### 3. Generate release notes

Gather commits since the last tag:

```bash
git log --oneline <last-tag>..HEAD --no-merges
```

Categorize by prefix:

- **What's New** — `feat:` commits
- **Bug Fixes** — `fix:` commits
- **Other** — remaining user-facing changes

Exclude:
- CI/workflow changes
- Test additions/fixes
- Documentation updates
- Internal refactoring with no user-visible effect

Writing style:
- Rewrite commit messages from the user's perspective, not the developer's
- Use present tense ("Add", "Fix", not "Added", "Fixed")
- Omit empty sections

### 4. Confirm with user

Show the draft:

```
## vX.Y.Z Release Notes

### What's New
- ...

### Bug Fixes
- ...

Ready to release? (Let me know if you want to edit.)
```

Do not proceed until the user approves. If they request edits, apply them and confirm again.

### 5. Trigger workflow

```bash
gh workflow run release.yml --repo mrskiro/stint -f version={version}
```

### 6. Watch workflow

```bash
sleep 5
gh run list --repo mrskiro/stint --limit 1
gh run watch {run_id} --repo mrskiro/stint
```

On failure, check logs and report the cause.

### 7. Update release notes

After the workflow succeeds, apply the confirmed notes to the GitHub Release:

```bash
gh release edit v{version} --repo mrskiro/stint --notes "..."
```

### 8. Done

Print the release URL: `https://github.com/mrskiro/stint/releases/tag/v{version}`
