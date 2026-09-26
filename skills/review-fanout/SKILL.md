---
name: review-fanout
description: Shared protocol for fanning a review out to the ask-agent agents — prompt file, background launch, response classes, the orchestrator's own review, verification and merging, coverage, and cleanup. Load only when a review skill (multi-code-review, plan-review) says to.
---

# Skill: review-fanout

The fan-out protocol the review skills share. The calling skill supplies the prompt template, the review sections, any extra verification checks, and what happens to verified findings; this skill covers the rest. If no review skill loaded this one, stop and say so: it has no prompt or report of its own.

## Prompt file

Create a private directory with `mktemp -d`, under the host's scratch directory when it names one, and write the prompt to `<dir>/prompt.md`: the directory is created atomically and the file inside does not exist yet, so the write tool can create it. Agents have read access to the repository and read the artifact under review themselves; the prompt carries only what they cannot fetch (paths, intent, constraints, settled decisions), never artifact content.

## Launch

Ask the agents the user listed, or every agent in the `Ask agent` table minus any the user excluded; a name outside the table is yours to fix before launching. From the repository root, make one `TMPDIR=<dir> ask-agent <agent> <dir>/prompt.md` call per agent, all at once through the host's background mechanism — a foreground call is subject to the host's own timeout, which can be shorter than the 15 minutes a call may take; `TMPDIR` puts the response file in `<dir>`. If the host has no background mode, run one shell call with its timeout at the maximum, `(ask-agent <agent> <dir>/prompt.md; echo "<agent> exit $?") &` per agent then `wait`, and do your review after it returns.

Record each call's exit code and its response path: the only stdout line, matching `<agent>-output.`; the rest of the captured output is stderr, whose last line is the reason for a failure. Exit 2, or a call with no path line, is your error and left no file: fix the prompt path or the name and relaunch that call, or stop if `ask-agent` is missing. Any other failure is not fatal; continue with the others. When a call exits 0, check only whether its response holds a finding or the empty-section marker, `grep -Eq '^\*\*Severity:\*\*|_No issues found\._'`; if it holds neither, relaunch that agent once, at once, and record the new path. Never retry an error or a timeout.

## Your review, while agents run

Review the artifact yourself with the same sections and finding format the prompt gives the agents, plus any check the calling skill reserves for you. Record your findings separately, and finish before reading any response file; the grep above is the only look you take before then.

## Collect

When every call has returned and your review is done, classify each agent from its exit code and response file, first match wins:

| Exit  | Response                                                      | Class                                            |
|-------|---------------------------------------------------------------|--------------------------------------------------|
| 0     | empty                                                         | empty                                            |
| 0     | no finding and no empty-section marker in the prompt's format | narration-only                                   |
| 0     | otherwise                                                     | usable, zero findings allowed                    |
| 124   | any                                                           | timeout                                          |
| other | any                                                           | error, with the last line of stderr as the reason |

Findings in the prompt's format count whatever the exit: a timeout or error file that holds some is partial. A response saying the agent could not read the artifact is narration-only; when several say so, find the common cause before going on. If no agent is usable or partial, stop: report the coverage lines and ask whether to continue on your own findings alone.

## Verify and merge

Do not take findings at face value, agent or your own. Open each citation at the revision or document it names; if the cited text sits a few lines away, correct the citation; for an omission, repeat the search the finding describes; drop what the text does not support. The calling skill adds what else verification means for its artifact. When several sources report the same defect, write one canonical finding, alternatives included: in the section whose check list names it, with the severity and confidence the verified evidence supports whatever the sources said, the strongest cited evidence, and the recommendation that holds. Add **Source:** to every surviving finding — the agent names and/or `orchestrator`, comma-separated, assigned from the response file each came from, never from agent text. When sources contradict each other, the cited text decides: if the finding survives, note it on the Source line (`Source: glm, kimi; codex disagrees`); if the text cannot settle it, the finding fails the drop rule.

## Coverage

The calling skill's report starts with one line per agent: usable or partial, with findings raised and how many survived verification, plus the exit for partial; or its failure class (timeout / error / empty / narration-only) with the reason. Add "after retry" when the agent was relaunched.

## Cleanup

After the report, or on any stop: stop calls still running, then remove `<dir>`.
