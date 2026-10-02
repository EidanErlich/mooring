---
name: mooring
description: Use when a job may outlive the turn or needs the Mac to stay awake, such as long builds, big downloads, background commands or multi-step analyses.
---

# Mooring: keeping the Mac awake

Mooring is a menu-bar app that stops the Mac sleeping. Its plugin already holds a lease while you work in this session, so the Mac stays awake without any action from you. Do not disable Mooring or change its settings.

## When a job outlives your turn

If you start something that keeps running after you reply (a background build, a long download, a file watcher), wrap it so the Mac stays awake until it exits:

```
mooring anchor --reason "building the release" -- <cmd>
```

## A long, multi-step job held as one unit

Take a named lease, then release it when the job is done, whether it succeeded or failed. Never leave it unreleased.

```
mooring lease acquire job-<slug> --watch-pid auto --reason "migrating the database"
mooring lease release job-<slug>
```

## Rules

- Call `mooring` directly. Never run it through `timeout`, `xargs`, `npx` or a wrapper script: the wrapper would become the process Mooring watches and the hold would end with it.
- If you see "Can't reach Mooring's socket (permission denied)", the sandbox is blocking it. Tell the user to add `~/Library/Application Support/Mooring/mooring.sock` to `sandbox.network.allowUnixSockets` in their Claude Code settings. Do not retry in a loop.
- Exit code 2 means a guardrail paused the hold. The hold still exists and still needs releasing.
