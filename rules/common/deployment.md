# Deployment to the User's Verification Environment

## Core Principle

After modifying code, ALWAYS deliver the build to the environment where the user
actually verifies the change — before declaring the work done.

Passing tests on the development machine is necessary but not sufficient.
"Done" means the user can see and touch the change in their own environment
(a physical device, a staging URL, an installed CLI — whatever the project's
verification surface is).

## Rules

1. **Every project defines its verification surface** in the project's
   instruction file (e.g. `CLAUDE.md`): where the user checks changes,
   and the one command that delivers a build there.
2. **Encapsulate delivery as a single script** (e.g. `deploy-device.sh`,
   `deploy-staging.sh`) checked into the repository. Multi-step delivery
   instructions in prose drift out of date; scripts do not.
3. **Verify order**: run the test suite first, then deliver. Never deliver
   a build with failing tests.
4. **Report delivery failures instead of skipping silently.** If the target
   is unreachable (device disconnected, staging down), say so explicitly and
   wait — do not mark the task complete.

## What stays project-specific

Device identifiers, signing identities, hostnames, and credentials belong in
the project repository (script + instruction file), never in these shared rules.

> **Language note**: Language-specific rules (e.g. `swift/deployment.md`)
> define the concrete delivery mechanics for their platform.
