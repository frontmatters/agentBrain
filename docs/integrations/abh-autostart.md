---
date: 2026-08-29
type: reference
tags: [integration, abh, autostart, launchd, systemd]
id: f12147c4-d7d8-5ab4-9e72-9b4155e1e083
---

# ABH Web autostart

ABH Web autostart is optional. It starts the user-owned ABH Web profile after
login or user-session boot. It does not run as root and it does not change the
canonical agentBrain source.

## Commands

```bash
brain harness autostart status
brain harness autostart enable
brain harness autostart disable
```

The implementation is:

```text
scripts/setup/setup-abh-autostart.sh
```

## Platform behavior

### macOS

Uses a user-level launchd agent:

```text
~/Library/LaunchAgents/com.agentbrain.harness.web.plist
```

It runs the resolved `abh` executable with:

```text
abh web --no-open
```

The service keeps the process alive and writes user-owned logs under the
agentBrain state directory.

### Linux

Uses a systemd user unit:

```text
~/.config/systemd/user/agentbrain-harness-web.service
```

The unit starts after `network-online.target`, restarts on failure, and uses the
user's `ABH_HOME`.

### WSL

If systemd user services are enabled, the Linux path applies. If systemd is not
available, the command reports that autostart cannot be enabled automatically.
The interactive ABH launcher remains available.

## Safety properties

- Autostart is never enabled silently.
- The service runs as the current user.
- `abh` must exist before enable succeeds.
- The resolved executable path is written into the service definition.
- Disable removes the service and stops it.
- Logs are user-owned.
- No credentials are copied into plist or unit files.

## Verification matrix

| Action | macOS | Linux | WSL |
|---|---|---|---|
| status without ABH | reports not installed | reports not installed | reports not installed |
| enable with ABH | launchd loaded | systemd user unit active | systemd path or clear refusal |
| status after enable | enabled | enabled | enabled or documented unavailable |
| disable | unloaded and removed | stopped, disabled and removed | same as platform path |
| restart | service recovers | service recovers | service recovers when supported |

Autostart is a convenience layer. It is not required for normal agentBrain
operation and should remain disabled by default.
