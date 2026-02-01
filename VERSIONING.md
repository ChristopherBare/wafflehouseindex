# Versioning System

This project uses automatic semantic versioning with commit-based build numbers.

## Version Format

```
MAJOR.MINOR.PATCH+BUILD_NUMBER
```

Example: `1.2.3+15` means version 1.2.3 with build 15

## How It Works

### Regular Commits (Automatic Build Numbering)

When you push to `master`, the build number automatically increments based on commits since the last tag:

1. Each push triggers a build
2. Build number = commit count since last tag
3. Version stays the same until you create a tagged release

Example workflow:
```
v1.0.0 (tagged)          → 1.0.0+1
  ↓ commit 1             → 1.0.0+2
  ↓ commit 2             → 1.0.0+3
  ↓ commit 3             → 1.0.0+4
v1.0.1 (tagged)          → 1.0.1+1
  ↓ commit 1             → 1.0.1+2
```

### Major Releases

To create a major release (e.g., 2.0.0, 2.01, etc.):

**Option 1: Using Git Tags (Recommended)**
```bash
git tag v2.0.0
git push origin v2.0.0
```

The workflow will:
- Extract version from tag (`v2.0.0` → `2.0.0`)
- Set build number to `1`
- Update `.version` file

**Option 2: Manual Workflow Trigger**
1. Go to GitHub Actions → "Build App Store Bundles"
2. Click "Run workflow"
3. Provide version name (e.g., `2.0.0`)
4. Provide build number (e.g., `1`)
5. Select build mode (release/debug)

## Version File (.version)

Located at `whi_flutter/.version`, tracks:

```json
{
  "major": 1,
  "minor": 0,
  "patch": 0,
  "last_tag": "v1.0.0",
  "last_commit": ""
}
```

This file is updated when creating major/patch releases. Git workflows handle it automatically.

## Version Script (scripts/get-version.sh)

Calculates versions based on:
- Current `.version` file state
- Git tag history
- Commit count since last tag

Usage:
```bash
./scripts/get-version.sh           # Get current version (auto-increment build)
./scripts/get-version.sh major     # Increment major version
./scripts/get-version.sh patch     # Increment patch version
```

Output:
```bash
version_name=1.0.0
build_number=2
is_major_release=false
```

## CI/CD Integration

Both workflows automatically use the versioning system:

### build-app-stores.yml
- Triggers on: push to master, tags, or manual workflow_dispatch
- Auto-increments build number for regular commits
- Uses manual inputs when provided
- Extracts version from tags

### auto-deploy-master.yml
- Triggers on: push to master (except markdown files)
- Auto-increments build number based on commits
- Deploys backend and apps together

## Examples

### Example 1: Regular Development
```
→ git push origin feature-branch
→ Create PR and merge to master
→ CI/CD builds with version 1.0.0+2
→ Artifacts available in GitHub Actions
```

### Example 2: Patch Release
```
→ ./scripts/get-version.sh patch  (1.0.0 → 1.0.1)
→ git add .version && git commit -m "Release 1.0.1"
→ git tag v1.0.1 && git push --tags
→ CI/CD builds with version 1.0.1+1
```

### Example 3: Major Release
```
→ ./scripts/get-version.sh major  (1.0.0 → 2.0.0)
→ git add .version && git commit -m "Release 2.0.0"
→ git tag v2.0.0 && git push --tags
→ CI/CD builds with version 2.0.0+1
```

## Build Artifacts

Artifacts are named with build mode:
- `android-app-bundle-debug` (for debug builds)
- `android-app-bundle-release` (for release builds)
- `ios-app-debug` / `ios-app-release`
- `linux-app-bundle`

For automatic pushes, build mode defaults to `debug` unless specified in workflow inputs.
