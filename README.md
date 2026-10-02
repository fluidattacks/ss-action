# Fluid Attacks SS

Free, open-source action to search for hardcoded secrets on your GitHub repositories.
No account, API key, or registration required to run the scan. Authentication is optional; see [Authentication](#authentication).

## Quick Start (2 minutes)

### 1. Create the GitHub Actions workflow

Add the file `.github/workflows/fa-secrets.yml` to your repository:

```yaml
name: SECRET_SCAN
on:
  push:
  pull_request:
    types: [opened, synchronize, reopened]
  schedule:
    - cron: '0 8 * * 1'  # optional: weekly full scan every Monday at 8am

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          # Required for differential scanning (default mode).
          # Can be omitted if scanner_mode: full is set.
          fetch-depth: 0

      - uses: fluidattacks/ss-action@<version>
        id: scan
```

Replace `<version>` with the latest release tag. Without a configuration file, the action scans the entire repository and writes results to `.fluidattacks-secret-scan-results.sarif`.

### 2. (Optional) Add a configuration file

To customize scan paths or output format, create a YAML file anywhere in your repository and pass its path to the action:

```yaml
- uses: fluidattacks/ss-action@<version>
  id: scan
  with:
    scan_config_path: .github/secret-scan-config.yaml
```

See [Configuration](#configuration) for the full list of options.

Commit and push. The scan will run automatically on the next push or pull request.

## Prerequisites

- A GitHub repository (public or private).
- GitHub Actions enabled on the repository.
- A **Linux runner** (`ubuntu-latest` or equivalent) — the action requires Docker, which is only available on Linux-hosted runners.
- No account, token, or API key is needed to run the scan. The action is 100% open source. Authentication is optional; see [Authentication](#authentication).

## Authentication

Authenticating attributes the run to your Fluid Attacks group and applies the group's platform policy. Set the `group` input and supply credentials in one of two ways.

### OpenID Connect (recommended)

No secret to store. Grant the job `id-token: write`:

```yaml
permissions:
  id-token: write
  contents: read
jobs:
  secret-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: fluidattacks/ss-action@<version>
        with:
          group: my-group
```

In Fluid Attacks, add a trust for issuer `https://token.actions.githubusercontent.com` with the bound claim `repository` = `my-org/my-repo` and enable it for the group. See the [OIDC federation guide](https://docs.fluidattacks.com/find-fix/use-cli/authentication/oidc-federation).

### Group token

```yaml
- uses: fluidattacks/ss-action@<version>
  with:
    group: my-group
    api_token: ${{ secrets.FLUID_GROUP_TOKEN }}
```

The token takes precedence over OIDC. `api_token` is ignored without `group`.

Authentication is best-effort: if `group` is invalid or no credentials are available (for example, pull requests from forks get neither `id-token` nor secrets), the action logs a warning and runs the scan unauthenticated.

## How it works

### Default branch detection

The action automatically detects your repository's default branch by running `git remote show origin`. This means it works with any branch name — `main`, `master`, `trunk`, `develop`, or whatever your team uses.

### Scan types

The action prefers differential scanning whenever a base is available, falling back to a full scan only when there is nothing to compare against:

| Trigger | Scan type | Base for comparison |
|---|---|---|
| Push to any branch | Differential scan | Commit before the push (`github.event.before`) |
| Pull request | Differential scan | PR base branch |
| Scheduled / manual trigger | Full scan | — |

You can force a full scan on every run with `scanner_mode: full` — see [Action inputs](#action-inputs).

### Why `fetch-depth: 0`?

The `actions/checkout` step uses `fetch-depth: 0` to download the full git history. This is required for differential scans: the action needs it to resolve the base commit and to detect your default branch via `git remote show origin`.

If you force `scanner_mode: full`, the action skips all git comparisons entirely, so a default shallow checkout is sufficient — `fetch-depth: 0` is not needed.

## Viewing results

After the workflow runs, results are written to the path configured in `output.file_path`, or to `.fluidattacks-secret-scan-results.sarif` when no configuration file is provided.

### SARIF file

The raw SARIF file is always available in your workspace. You can download it as an artifact, process it with other tools, or upload it to a third-party platform.

### GitHub Security tab (optional)

You can upload the SARIF file to GitHub's Security tab so findings appear as **Code scanning alerts** with inline PR annotations:

```yaml
- name: Upload results to GitHub Security tab
  if: always()
  uses: github/codeql-action/upload-sarif@v4
  with:
    sarif_file: ${{ steps.scan.outputs.sarif_file }}
```

> **Restrictions:** SARIF upload to the Security tab requires **GitHub Advanced Security**, which is available on all public repositories and on private repositories under a GitHub Advanced Security license. On private repositories without that license, the upload step will fail. See [GitHub's documentation](https://docs.github.com/en/code-security/code-scanning/integrating-with-code-scanning/uploading-a-sarif-file-to-github) for details.

## Configuration

When `scan_config_path` is provided, the action uses that file exclusively. When omitted, the action runs with built-in defaults: scans the entire repository and writes results to `.fluidattacks-secret-scan-results.sarif`.

Only the `ss` and `output` keys are used by this action.

```yaml
ss:
  include:
    - .          # paths to scan
  exclude:
    - tests/     # paths to skip

output:
  file_path: .fluidattacks-secret-scan-results.sarif
  format: SARIF
```

### `ss.include`

A list of paths (files or directories) to scan.

- **Full scan**: uses this list, defaulting to `.` (entire repository) if not set.
- **Differential scan**: always uses the list of changed files, regardless of this setting.

### `ss.exclude`

A list of paths to exclude from the scan. Applied in both full and differential modes.

### `output`

Controls the results file written to the repository workspace.

| Field | Default | Description |
|---|---|---|
| `file_path` | `.fluidattacks-secret-scan-results.sarif` | Path to the results file |
| `format` | `SARIF` | Output format (`SARIF` or `CSV`) |

## Action inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `scan_config_path` | No | — | Path to the YAML configuration file, relative to the repository root. When omitted, the action runs with built-in defaults. The job fails if the file does not exist at the given path. |
| `scanner_mode` | No | _(auto)_ | Override the scan mode. `full` forces a full repository scan. If omitted, the mode is determined automatically based on the event and branch. |

### `scan_config_path`

Point the action at your configuration file:

```yaml
- uses: fluidattacks/ss-action@<version>
  id: scan
  with:
    scan_config_path: .github/secret-scan-config.yaml
```

The path is relative to the repository root. The job fails immediately if the file does not exist.

### `scanner_mode: full`

Forces a full repository scan regardless of the event. Useful for scheduled audits or when you want every run to cover the entire codebase.

```yaml
- uses: fluidattacks/ss-action@<version>
  id: scan
  with:
    scanner_mode: full
```

## Action outputs

| Output | Description |
|---|---|
| `sarif_file` | Path to the SARIF results file |
| `vulnerabilities_found` | `true` if any vulnerabilities were detected, `false` otherwise |

You can use these outputs in subsequent workflow steps. For example:

```yaml
- name: Comment on PR
  if: steps.scan.outputs.vulnerabilities_found == 'true'
  run: echo "Vulnerabilities were found. Check the Security tab for details."
```

## Common scenarios

### Monorepo: scan only specific folders

```yaml
ss:
  include:
    - services/api/
    - services/web/
  exclude:
    - services/legacy/
```

### Export results as CSV

```yaml
output:
  file_path: results.csv
  format: CSV
```

## Troubleshooting

### The scan runs but no results appear in the Security tab

Make sure the "Upload SARIF" step is included in your workflow and uses `if: always()` so it runs even if the scan finds vulnerabilities.

### The differential scan analyzes all files instead of just changes

Verify that `fetch-depth: 0` is set in the `actions/checkout` step. Without full git history, the action cannot determine which files changed.

### The action doesn't detect my default branch

The action runs `git remote show origin` to detect the default branch. This requires `fetch-depth: 0` in the checkout step so the remote metadata is available. If detection fails, verify that the `origin` remote is correctly configured in your repository.

### The job fails with "not found in repository"

The path provided to `scan_config_path` does not exist in the repository. Verify the path is correct and relative to the repository root.

## More information

- [Source code on GitHub](https://github.com/fluidattacks/ss-action)
- [Vulnerability database](https://db.fluidattacks.com)
- [Fluid Attacks documentation](https://docs.fluidattacks.com)
- [SARIF format specification](https://sarifweb.azurewebsites.net/)
