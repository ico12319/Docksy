# Docksy

Your little companion for big dev days.

Docksy is a small macOS desktop mascot that keeps Kubernetes contexts, database tunnels, favourite links, and developer shortcuts within reach. Choose a gopher, cat, or dog, then click it—or its menu-bar icon—to open the tools you use throughout the day.

Built with Swift, AppKit, and Core Animation. No package dependencies, hosted service, or account required.

## What problems does it solve?

- **Switching between clusters:** see your current Kubernetes context and select another from a menu instead of remembering context-switching commands.
- **Repeated database port-forward commands:** save each database's namespace, resource, and ports once, then start its tunnel from the menu.
- **Keeping track of tunnels:** see Connecting, Connected, or Failed, and stop the app-owned tunnel without finding and killing a process manually.
- **Scattered developer shortcuts:** keep favourite URLs, ChatGPT, and running local Codex terminals in one launcher.

The mascot is a movable, resizable desktop companion. Kubernetes and database configuration are personal to each user; no organization-specific clusters, database targets, or favourite links are shipped as defaults.

## Requirements

| Feature | What you need |
| --- | --- |
| Build and run | Apple silicon Mac, macOS 13 or later, Xcode Command Line Tools |
| Kubernetes context picker | `kubectl` and an existing kubeconfig containing your contexts |
| Database port-forwarding | Cluster access, required authentication tools, permission to port-forward to the target, and an available local port |
| Connect to a forwarded database | A database client and the database's normal credentials |
| ChatGPT shortcut | An installed ChatGPT desktop app |
| Codex terminal shortcuts | A running local Codex CLI session in Terminal or iTerm2 |

Kubernetes features look for `kubectl` on the app's PATH and in `/opt/homebrew/bin` or `/usr/local/bin`. Connect your VPN and complete your cluster provider's login steps if required. The mascot and favourite links can be used without Kubernetes, ChatGPT, or Codex.

## Build and launch

### Guided setup with Codex or Claude

Clone this repository and open it in a local Codex or Claude Code session with filesystem and terminal access. Give the assistant this prompt:

> Read `skills/docksy-setup/SKILL.md` and follow it to set up and launch Docksy on my Mac. Ask me for any missing Kubernetes or database details, and preserve my existing settings.

The [setup skill](skills/docksy-setup/SKILL.md) checks prerequisites, asks which features you want, helps configure your kubeconfig and database targets, validates the settings, and builds or reuses the app before launching it. It uses your existing cluster credentials; it does not ask for database passwords. It also accounts for active tunnels before rebuilding or restarting.

This prompt works by having the assistant read the skill directly; no global skill installation is required. Launch-only requests reuse an existing app. The assistant still needs your answers and any permissions required by its environment. If it cannot access your Mac, it can guide you through the manual steps instead.

### Manual setup

From the project directory:

```sh
zsh test.sh
zsh build.sh
open 'dist/Docksy.app'
```

`test.sh` runs unit checks only. `build.sh` creates the app bundle in `dist/`. You can also open that bundle from Finder.

Quit a running copy before rebuilding. The build targets Apple silicon, is locally ad-hoc signed, and is not notarized. The app does not install itself into Applications or start automatically at login.

## Configure your Kubernetes contexts

The app uses your existing kubeconfig; it does not create clusters or ask you to paste credentials into its settings.

1. Set up cluster access with your provider's normal login or kubeconfig instructions.
2. Ensure the contexts are in `~/.kube/config`, or configure a custom kubeconfig path as shown below.
3. Open **Kubernetes context** in the mascot menu. The **Current:** label and checkmark identify the selected context.
4. Choose a context to make it the default. Use **Refresh contexts** after adding or changing contexts outside the app.

You can list context names in a terminal with:

```sh
kubectl config get-contexts -o name
```

Choosing a context updates kubeconfig's current context, affecting terminals and tools using the same configuration. Listing and switching contexts only access local configuration; they do not verify connectivity or log in to a cluster. Existing database forwards remain on their explicitly selected context.

### Use a custom kubeconfig

Choose **Kubernetes context → Settings…** to open the app's local `config.json` in TextEdit. For a custom kubeconfig without database targets, use:

```json
{
  "kubeconfig": "~/clusters/config",
  "databaseTargets": []
}
```

Save the file, then choose **Reload settings**.

`kubeconfig` is optional. It accepts one absolute file path or a path beginning with `~/`. If omitted, kubectl uses its normal defaults: the `KUBECONFIG` environment inherited by the app, or `~/.kube/config`. Inherited `KUBECONFIG` can refer to merged files. A Finder-launched app does not normally inherit environment variables exported in a terminal, so use the setting when you need a specific file.

Use trusted kubeconfig files: their authentication plugins can execute programs under your account.

## Configure your databases

New installations start with no database targets. To add yours:

1. Choose **Database port-forward → Settings…**.
2. On first use, the app creates a generic example `config.json`. Replace the examples with your own values.
3. Save as plain JSON in TextEdit.
4. Choose **Reload settings**. Stop any active forward and wait for context operations before reloading.
5. Choose **Database port-forward → context name**. If that context has multiple database targets, choose one from its submenu.

The same settings file is available from either Kubernetes menu. Settings live at `~/Library/Application Support/Docksy/config.json`, outside the project. You do not need to edit the source code or rebuild the app to change them.

### Example: PostgreSQL

This configuration forwards a PostgreSQL service in the `databases` namespace to port `15432` on your Mac:

```json
{
  "databaseTargets": [
    {
      "name": "Development PostgreSQL",
      "context": "my-dev-cluster",
      "namespace": "databases",
      "resource": "service/postgres",
      "localPort": 15432,
      "remotePort": 5432
    }
  ]
}
```

Replace `my-dev-cluster`, `databases`, and `service/postgres` with your actual context, namespace, and service name. Once the menu shows **Connected**, configure your database client with:

| Client setting | Value for this example |
| --- | --- |
| Host | `127.0.0.1` |
| Port | `15432` |
| Database name | Your database's name |
| Username and password | Your normal database credentials |
| TLS settings | Whatever your database requires |

Database credentials belong in your client. The app creates the tunnel and does not store database usernames or passwords.

### Settings reference

The top-level JSON object contains `databaseTargets` and, optionally, `kubeconfig`. Each database target supports:

| Field | Required? | Meaning |
| --- | --- | --- |
| `name` | Yes | A unique display name for the target |
| `context` | No | Exact kubeconfig context name; omit to offer this target for every context |
| `namespace` | Yes | Kubernetes namespace containing the resource |
| `resource` | One target method | `service/name`, `deployment/name`, or `pod/name` |
| `podNamePrefix` | Alternative to `resource` | Prefix used to find a running pod when its full name changes |
| `localPort` | Yes | Available port on your Mac, from 1 to 65535 |
| `remotePort` | Yes | Remote port, from 1 to 65535; for a service, use its service port |

Set **exactly one** of `resource` or `podNamePrefix`. For services, kubectl resolves the service port to the pod's target port. For a pod-name prefix, the app ignores terminating and non-running pods, prefers Ready pods, then chooses by name. Prefix discovery requires permission to list pods in the namespace.

For example, to discover pods whose names start with `postgres-`, replace:

```json
"resource": "service/postgres"
```

with:

```json
"podNamePrefix": "postgres-"
```

Add more objects to `databaseTargets` for additional databases. With one matching target, clicking the context connects directly. With multiple targets, the submenu shows their names and local endpoints. See [examples/config.json](examples/config.json) for PostgreSQL and MySQL examples.

Invalid JSON or settings display an error and block new Kubernetes actions until corrected. The last loaded configuration is retained in memory. Fix the file and choose **Reload settings** again.

### Tunnel behavior

- Tunnels bind only to `127.0.0.1`.
- Every database command specifies its context and namespace explicitly.
- Only one tunnel runs at a time. Stop it before choosing another database.
- **Cancel connection / Stop port-forward** stops only the app-owned process. Quitting the app also stops it.
- The app never kills another application's listener to free a port.
- Connection attempts time out after 60 seconds. A disconnected tunnel needs an explicit reconnect.
- **Connected** confirms the local listener is ready; it does not confirm a successful database login or query.

## Mascot and everyday shortcuts

- **Mascot → Gopher / Cat / Dog:** switch artwork immediately; the choice is remembered across restarts.
- **Move:** drag the mascot, including across displays or partially off-screen. Use **Reset mascot position** to recover it.
- **Resize:** scroll or pinch, or use **Size → Smaller / Larger / Reset size**. Size and position persist. Default height is 140 points; the range is 64–1200 points.
- **Motion:** the gentle breathing animation follows macOS Reduce Motion.
- **Favourite links → Add link…:** save a unique name and an HTTP/HTTPS URL. Saved links survive upgrades, including encoded paths and fragments.
- **Open ChatGPT:** open the installed desktop app.
- **Codex terminals:** select an existing local Terminal/iTerm2 tab. The app does not type commands into terminals or read terminal contents. tmux, SSH, and editor terminals are not supported. The first selection may request macOS Automation permission.

### Personal gopher artwork

The repository and distributed app include the DOCKSY sign. To keep a personal gopher on your own Mac, place a transparent PNG at `~/Library/Application Support/Docksy/gopher.png`. Docksy uses that file for the desktop gopher and its menu-bar image; cat and dog choices keep their bundled artwork. Restart Docksy, or switch away from Gopher and back, to load a changed file. Remove the personal file to return to the bundled design. Personal artwork stays outside the repository and source archive.

Restarting stops an active database tunnel, so finish or stop the connection first.

## Troubleshooting

| Problem | What to check |
| --- | --- |
| No contexts appear | Verify your kubeconfig path and that `kubectl config get-contexts -o name` lists contexts using that configuration. Then refresh. |
| kubectl is missing | Install it in a supported location or make it available on the app's PATH. |
| A database target is missing | Check its optional `context` matches exactly, then reload settings. |
| Connection fails | Check VPN, authentication, namespace, resource name, and permissions. Use the menu's error details. |
| Local port is already in use | Choose another `localPort`, save, and reload settings. |
| Tunnel connects but database login fails | Check the database client's credentials, database name, and TLS settings. |
| Reload settings is disabled | Stop the active tunnel and wait for context operations to finish. |
| Terminal selection is denied | Allow the app's Terminal/iTerm2 access in System Settings → Privacy & Security → Automation. |

## Project layout and development

| Location | Contents |
| --- | --- |
| `Sources/` | Swift app, configuration validation, Kubernetes commands, and launcher code |
| `Tests/` | Isolated unit checks |
| `assets/` | Mascot images, generation prompts, app metadata, and terminal scripts |
| `examples/config.json` | Shareable example settings |
| `skills/docksy-setup/` | Guided agent setup and a configuration checker using the app's validation rules |
| `dist/` | Built application bundle; excluded from source control |
| `.build/` | Compiler output and local build artifacts; excluded from source control |

Run `zsh test.sh` for unit checks covering configuration, context parsing, literal command arguments, pod selection, forward lifecycle/readiness, an in-process pipe, session parsing, geometry, artwork, and favourite links. The checks never launch kubectl, switch contexts, open websites, or access a cluster or database. No integration or end-to-end tests are included.

For the setup skill's configuration helper, run `zsh skills/docksy-setup/scripts/test-check-config.sh`. It compiles the configuration model and uses temporary files to check valid settings, invalid ports, missing files, paths with spaces, and preservation of the candidate files. It does not launch the app or access Kubernetes.

## Privacy and sharing

User settings stay outside the repository. Mascot preferences and favourite links are stored in the app's macOS preferences. Kubernetes credentials remain managed by kubectl. The app has no telemetry or credential upload.

Error messages can contain context names and kubectl output; redact those before sharing bug reports. Do not commit personal kubeconfig, settings, exported preferences, or credentials. `.local/`, `.build/`, `dist/`, and local `config.json` files are ignored; only `examples/config.json` is a shared example. Build outputs and local backups are not source release material.

## License and artwork

Code: [MIT License](LICENSE).

The Go gopher design is by Renée French and licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/); see [The Go Gopher](https://go.dev/blog/gopher). This app uses an AI-generated adaptation with a cyan rendering and a wooden DOCKSY sign. Keep the attribution when distributing the gopher or derived app icon. [NOTICE.md](NOTICE.md) records the artwork provenance and terms. Generation prompts are in `assets/`. The code license does not replace the gopher artwork's attribution requirements.
