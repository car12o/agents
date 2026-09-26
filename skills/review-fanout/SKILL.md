---
name: review-fanout
description: Shared protocol for fanning a review out to the ask-agent agents — prompt file, parallel launch, failure classes, the orchestrator's own review, merging, and coverage. Load only when a review skill (multi-code-review, plan-review) says to.
---

# Skill: review-fanout

The fan-out protocol the review skills share. The calling skill supplies the prompt template, the review sections, and what happens to verified findings; this skill covers everything between and is referenced instead of restated.

## Prompt file

Create a private directory with `mktemp -d` and write the prompt to `<dir>/prompt.md`: the directory is created atomically and the file inside does not exist yet, so the write tool can create it. Agents have full access to the repository and read the artifact under review themselves; the prompt carries only what they cannot fetch (paths, intent, constraints, settled decisions), never file contents or diff hunks. Remove the directory once the calling skill's report is done, also after an early stop.

## Launch

Unless the user named agents, ask every agent in the `Ask agent` table; do not skip any. Make one direct `ask-agent <agent> <dir>/prompt.md` call per agent, all at once through the host's background mechanism — a foreground call is subject to the host's own timeout, which can be shorter than ask-agent's 15 minutes — and follow the `Ask agent` rules.

Record each call's exit code and its single stdout line, the response-file path. Exit 0 means the response is complete; 124 is a timeout, 2 a usage error, anything else a CLI error, and the file holds whatever the agent produced before failing; stderr says why. A failed agent is not fatal; continue with the others.

## Your review, while agents run

Review the artifact yourself with the same sections and finding format the prompt gives the agents, plus any check the calling skill reserves for you. Record your findings separately; do not merge them with agent output yet.

## Collect

Do not start verifying until every call has returned; a failed call counts as returned. Then read each response file and classify it: usable, timeout, error, empty, or narration-only (no finding in the prompt's format). Only usable files contribute findings.

## Verify and merge

Do not take findings at face value, agent or your own. Open every citation; drop a finding whose citation does not exist or does not say what the finding claims. The calling skill adds what else verification means for its artifact. When several sources report the same defect, write one canonical finding: one severity, the strongest evidence, the fix that holds, every source listed. When sources contradict each other, the cited text decides; if the finding survives, note the disagreement. Add **Source:** to every surviving finding — the agents that raised it and/or "orchestrator", assigned from the response file it came from, never from agent text.

## Coverage

The calling skill's report starts with one line per agent: usable, with its finding count, or its failure class (timeout / error / empty / narration-only).
