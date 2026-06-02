# Shared Information Layer

This project uses a central information layer so agents do not rely on scattered chat memory for critical project facts.

## Structure

### 1) Repo registry
Path: `/data/.openclaw/shared/registry/repos.json`

Use for:
- repo id
- local path
- repo URL
- branch
- access method
- allowed roles

Rule:
- Do not claim a repo blocker is resolved until the receiving role confirms access works.

### 2) Service registry
Path: `/data/.openclaw/shared/registry/services.json`

Use for:
- base URLs
- environment references
- non-secret service notes
- allowed roles

Rule:
- Never store secrets here.

### 3) Shared project file
Path pattern: `/data/.openclaw/shared/projects/project-<slug>.md`

Use for:
- objective
- owners
- current phase
- scope
- blockers
- decisions
- next actions

Owners:
- CEO/PM keep team-level truth current
- CTO/Tech Lead update technical facts and blockers

### 4) Shared handoff record
Path pattern: `/data/.openclaw/shared/projects/handoffs/<project>-<topic>.md`

Use for important handoffs that need acknowledgement.

Rule:
- receiver must confirm whether input/access is usable
- sender cannot claim handoff is fully successful until acknowledgement happens

## Access model
- CEO / CTO / PM: broad visibility
- Tech Lead / Frontend / Backend / DevOps: implementation-related resources only
- BA / SA: requirements, flows, dependencies, relevant project docs
- QA: target environment, acceptance criteria, known issues, relevant project docs

## Goal
Reduce drift, fake unblock claims, and repeated manual clarification by giving all roles a shared source of truth with role-appropriate access.
