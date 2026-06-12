# AGP — Agent Governance Plane

**Community Edition** · by [Raksha AI](https://docs.getraksha.com) — *Operational Safety for Agentic AI*

AGP is the runtime enforcement layer that sits between AI agents and every MCP tool they can invoke. Every agent-to-tool call passes through AGP: the agent is authenticated, its behavior profile is checked, policy is evaluated, and risky operations are held for human approval — **before** a single byte reaches the tool backend. Everything is recorded in an append-only audit trail.

If you run AI agents (Claude Desktop, Claude Code, Cursor, VS Code, Codex, or your own) against MCP servers and want to answer *"which agent can do what, who approved it, and what actually happened?"* — this is the missing layer.

```
agent (MCP client) ──► AGP proxy ──► policy / profile / approval ──► your MCP servers
                            │
                            └──► append-only audit trail + admin console
```

## What's in Community Edition

- **8 services**, single static binaries, zero infrastructure — state lives in SQLite under `~/.agp`
- **`agp` CLI** — one binary that installs, starts, and manages the whole stack
- **Admin console** — web UI for agents, behavior profiles, the tool catalog, approvals, and a live activity feed
- **AGP Connect** — stdio bridge that plugs Claude Desktop, Claude Code, Cursor, VS Code, and Codex into the governed proxy
- **Fail-closed by default** — an agent can only call tools explicitly granted in its approved behavior profile; risky operations are held for human approval

## Quickstart

```sh
# 1. Install the CLI
curl -fsSL https://raw.githubusercontent.com/getraksha/agp/main/install.sh | sh

# 2. Initialize ~/.agp (secrets, per-service config, CLI profile)
agp init

# 3. Download the service binaries for your platform
agp fetch all

# 4. Start the stack (8 services, health-checked)
agp start all
agp status

# 5. Create your first governed agent and connect a client
agp setup --agent-id my-agent --client claude-desktop
```

The admin console is at `http://localhost:8090` (credentials are printed by `agp init`).

## Supported platforms

| OS      | Architectures   |
|---------|-----------------|
| macOS   | arm64, amd64    |
| Linux   | amd64, arm64    |

Windows is not supported yet.

## Releases & verifying downloads

Binaries are published as [GitHub Releases](https://github.com/getraksha/agp/releases). Each release ships a `manifest.json` (per-asset SHA-256 checksums) and a `SHA256SUMS` file. The `agp` CLI and the install script verify checksums automatically before installing anything.

To verify manually:

```sh
shasum -a 256 -c SHA256SUMS --ignore-missing
```

## What this repository is (and isn't)

This repository is the **distribution channel** for AGP Community Edition: the README you're reading, the install script, and the release binaries. The AGP source code is **not public**. The install script is MIT-licensed; the binaries are free to use under the [Community License](LICENSE.md).

## Documentation

- [docs.getraksha.com](https://docs.getraksha.com) — architecture, concepts, threat models
- `agp help` — full CLI reference

## Support

Questions, bug reports, and feature requests: [GitHub Issues](https://github.com/getraksha/agp/issues).

---

© Raksha AI. AGP Community Edition is free to use under the [Community License](LICENSE.md).
