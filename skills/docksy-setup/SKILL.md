---
name: docksy-setup
description: Set up, configure, build, and launch the Docksy macOS desktop companion from its repository. Use when someone wants guided Docksy setup, their own Kubernetes contexts or database targets, or help launching an existing installation.
---

# Set up Docksy

Get the user's Docksy running with the features they want. Use the existing app and build scripts; this is setup, not an app-development task. A launch-only request should reuse an existing installation without rewriting settings or rebuilding it.

## Find the app and prerequisites

- In this repository the skill lives at `skills/docksy-setup/`. Locate the checkout containing `README.md`, `build.sh`, and `Sources/Configuration.swift`. If the skill was copied elsewhere, use the user's checkout or ask where it is. Do not assume a particular home directory or download a different project.
- Read the checkout's [README](../../README.md), `build.sh`, and `Sources/Configuration.swift` before setup. They are the source of truth for supported platforms, paths, and settings. The current build needs Apple silicon, macOS 13+, and Xcode Command Line Tools.
- Check for an existing `dist/Docksy.app` and a running instance before launching. Read the bundle identifier from `assets/Info.plist`; it intentionally retains a legacy value so existing preferences survive branding changes. An older-named copy may be running under the same identifier.
- For source builds, check `xcrun --find swiftc`. For Kubernetes features, check for `kubectl` and the user's existing kubeconfig. Missing Kubernetes tooling does not prevent using the mascot and links. Explain missing prerequisites and ask which optional features they want before proposing installations. Do not install an entire package manager, move the app to Applications, or enable login startup as part of ordinary setup.

## Ask only for missing choices

Reuse information already supplied by the user and their existing Docksy settings. If intent is unclear, ask whether they want the mascot/shortcuts only, Kubernetes context switching, or database forwarding too. Do not make optional mascot and favourite-link choices block launch; those have menus in the app.

For Kubernetes, resolve which kubeconfig the user wants. Default to an existing `~/.kube/config` unless they have selected another file. A Finder-launched app may not inherit a shell's `KUBECONFIG`; for a custom single file, store its path in Docksy's optional `kubeconfig` setting. If the user relies on merged files, explain that a single custom path is different and preserve their intended configuration.

List **context names only**, using `kubectl config get-contexts -o name` with the selected configuration. Read the current context with `kubectl config current-context` if needed; an unset current context is not a reason to discard the others. These are local configuration reads. Do not print raw kubeconfig, tokens, certificates, or private keys. Do not switch contexts, contact clusters, or start a port-forward just to verify setup.

For each database target, gather the following in one concise question when possible:

| Detail | What to ask |
| --- | --- |
| Context scope | Which discovered context, or explicitly all contexts? |
| Namespace | Which namespace contains the database resource? |
| Target | A `service/name`, `deployment/name`, `pod/name`, or a pod-name prefix? |
| Remote port | Which service or pod port should be forwarded? |
| Local port | Which available port on the Mac should the client use? |
| Display name | Use a clear unique name based on their answer, asking only if ambiguous. |

If the user does not know the namespace/resource, ask for those details or whether they want a scoped, read-only cluster lookup. An explicit request for that lookup authorizes it; routine setup does not imply remote discovery. Do not guess a target from unrelated clusters. Never request database passwords: the database client uses them separately.

## Configure without losing existing settings

The current settings path is `~/Library/Application Support/Docksy/config.json`. Inspect it if present. If it contains invalid JSON, explain the issue and retain the original rather than treating it as an empty installation.

Use the schema in `Sources/Configuration.swift` and [examples/config.json](../../examples/config.json). The root requires `databaseTargets` (an array, possibly empty) and optionally `kubeconfig`. Each target requires a unique `name`, `namespace`, integer `localPort` and `remotePort` in 1–65535, and exactly one of `resource` or `podNamePrefix`. Omit `context` only when the user wants the target offered for all contexts. For a service, `remotePort` is its service port.

For a mascot-only or context-picker-only setup, leave existing database targets intact. A new installation can use `{"databaseTargets": []}`. Example target names in the repository are templates, not the user's actual infrastructure.

For requested changes:

1. Prepare the candidate JSON outside the tracked repository, preserving unrelated settings and existing targets. If a proposed target name already exists, update it only when the user requested that change; otherwise resolve the collision with them.
2. Validate the candidate with the existing Swift model through the included checker (requires Xcode Command Line Tools):

   ```sh
   zsh "$skill_dir/scripts/check-config.sh" "$repo_root" "$candidate_json"
   ```

   Set those variables to the actual paths first. The checker only reads the candidate and compiles the configuration model; it does not launch Docksy or kubectl. If the developer tools are unavailable, report that validation is pending rather than claiming the checker passed.
3. Before replacing existing settings, retain a timestamped backup beside them. Write the validated candidate atomically. Preserve any newer edits made since you read the original; re-read and merge if it changed. Keep the directory private and the settings file readable only by the user. Do not put personal settings or backups into the repository.

Leave saved favourite links, mascot choice, size, and position alone unless the user asks to change them. Preserve a personal `~/Library/Application Support/Docksy/gopher.png` override. The public `assets/gopher.png` must keep its DOCKSY sign.

## Build or reuse, then launch

If the user only wants to launch an existing usable app, reuse it. If a build is needed, first inspect `test.sh` and confirm it still runs only unit checks. From the checkout, run:

```sh
zsh test.sh
zsh build.sh
codesign --verify --strict --verbose=2 'dist/Docksy.app'
plutil -lint 'dist/Docksy.app/Contents/Info.plist'
```

Do not overwrite a running executable. Check the app's database menu before quitting or restarting: either action stops its tunnel. If an active connection exists and the user has not authorized disconnecting it, leave that app running and finish work that does not require a restart. State what remains pending. If you cannot determine whether a connection is active, ask before restarting. Close only Docksy, never terminals, database clients, or other apps.

Retain the previous working bundle before replacing it. Diagnose failed builds before attempting to launch their output. A known sandbox issue can make `iconutil` report `Invalid Iconset` for valid PNGs: inspect the icon dimensions, then request the environment's required permission to retry the converter outside its sandbox and complete signing. Do not bypass execution approvals, Gatekeeper, or Automation permissions.

If Swift reports a module-cache path mismatch after a checkout was copied or moved, move the generated `.build/module-cache` aside and rebuild it. Do not remove user settings to fix a compiler cache.

For an already-running app, use **Reload settings** after saving, when no tunnel or context operation is active. A launch-only request should not disturb it. Otherwise open the exact verified bundle through the available app-launch tool, or:

```sh
open "$repo_root/dist/Docksy.app"
```

Use the permissions required by the assistant's environment. If UI inspection is available, confirm Docksy appears and inspect its menus without selecting a cluster or starting a connection. Without UI access, distinguish a successful launch command from an unverified visible UI. This local build is ad-hoc signed and not notarized; do not claim otherwise.

## Handoff

Report where the app and settings live, which features were configured, and what the user should click next. For configured targets, give their local client endpoints, such as `127.0.0.1:15432`, without implying a tunnel is already running. Mention any unavailable dependency or deferred reload/restart. Do not report database connectivity as tested unless the user explicitly requested a connection and it was actually checked. Never run integration or end-to-end tests during this workflow.
