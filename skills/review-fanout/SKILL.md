---
name: review-fanout
description: Shared protocol for fanning a review out to the ask-agent agents — prompt file, agent selection, background launch, retry by resume, response classes, the orchestrator's own review, verification and merging, coverage, and stopping calls. Load only when a review skill (multi-code-review, plan-review) says to.
---

# Skill: review-fanout

The fan-out protocol the review skills share. The calling skill supplies the prompt template, the review sections, any extra verification checks, and what happens to verified findings; this skill covers the rest. If no review skill loaded this one, stop and say so: it has no prompt or report of its own. Load the `ask-agent` skill too: it defines the call, its output, and its exit codes; `<ask-agent>` below is its script's full path.

## Prompt file

Create a private directory with `mktemp -d`, under the host's scratch directory when it names one, and write the prompt to `<dir>/prompt.md`: the directory is created atomically and the file inside does not exist yet, so the write tool can create it. Agents have read access to the repository and read the artifact under review themselves; the prompt carries only what they cannot fetch (paths, intent, constraints, settled decisions), never artifact content.

## Launch

Ask the agents the user listed, or every agent `<ask-agent> --list` prints minus any the user excluded; a name outside that list is yours to fix before launching. From the repository root, make one `TMPDIR=<dir> <ask-agent> <agent> --prompt-file <dir>/prompt.md >/dev/null` call per agent, all at once, in the background as the ask-agent skill's rules say; `TMPDIR` keeps every run in `<dir>`. Discarding stdout, which carries the response, keeps every response out of your context until you collect it, so the captured output is ask-agent's own status lines alone. If the host has no background mode, do your review after the calls return.

Record each call's exit code and, from its last `ask-agent: run <run> turn <N>, …` line, its run and turn: the response is `<run>/turn-<N>/response.md`. The first such line appears as the agent starts, so a call killed before its summary still names its run. A call with no `ask-agent: run` line never started a run and is your error: exit 64 is bad usage, 126 or 127 a wrong script path; fix the call and relaunch it, or stop if the script is missing. Any other failure is not fatal; continue with the others.

## Retry by resume

An agent gets at most one retry: a resume of its own run, launched at once in the background like the first call, so it keeps everything it already read. Pass the retry prompt on stdin, `<ask-agent> --resume <run> [--timeout 10m] >/dev/null <<'EOF'`:

- Exit 0 and the response holds neither a finding nor the empty-section marker, `grep -Eq '^\*\*Severity:\*\*|_No issues found\._'`: "Your answer is missing or incomplete. Output your complete answer now, in exactly the format the first message specified."
- Exit 124 or 137, with `--timeout 10m`: "Time is up. Stop investigating and output what you have found so far, in exactly the format the first message specified."
- Any other non-zero exit whose reason shows a transient failure — a dropped connection, a rate limit (HTTP 429), a server error (HTTP 5xx), or an overloaded provider: "The previous attempt failed mid-answer. Continue, and output your complete answer in exactly the format the first message specified."

Never retry a permanent failure — an exhausted quota or usage limit, an authentication failure, an unknown model, an invalid option, a context-length limit, any other HTTP 4xx — a stopped call (exit 143), or a failure whose reason names no cause. If the resume exits 64 because the run has no session, launch the agent afresh instead; that is still its one retry. The retry's exit code, run, and turn become the agent's; its first response still counts at Collect. That grep is the only look you take at a response before your own review is done.

## Your review, while agents run

Review the artifact yourself with the same sections and finding format the prompt gives the agents, plus any check the calling skill reserves for you. Record your findings separately, and finish before reading any response file; the grep above is the only look you take before then.

## Collect

When every call has returned and your review is done, classify each agent from its last call's exit code and response file, first match wins; findings in the prompt's format count from every response the agent produced, its first call's included:

| Exit  | Response                                                      | Class                                                      |
|-------|---------------------------------------------------------------|------------------------------------------------------------|
| 0     | empty                                                         | empty                                                      |
| 0     | no finding and no empty-section marker in the prompt's format | narration-only                                             |
| 0     | otherwise                                                     | usable, zero findings allowed                              |
| 124, 137 | any                                                        | timeout                                                    |
| other | any                                                           | error, with the reason from the last status line           |

Findings in the prompt's format count whatever the exit: a timeout or error file that holds some is partial. A response saying the agent could not read the artifact is narration-only; when several say so, find the common cause before going on. If no agent is usable or partial, stop: report the coverage lines and ask whether to continue on your own findings alone.

## Verify and merge

Do not take findings at face value, agent or your own. Open each citation at the revision or document it names; if the cited text sits a few lines away, correct the citation; for an omission, repeat the search the finding describes; drop what the text does not support. The calling skill adds what else verification means for its artifact. When several sources report the same defect, write one canonical finding, alternatives included: in the section whose check list names it, with the severity and confidence the verified evidence supports whatever the sources said, the strongest cited evidence, and the recommendation that holds. Add **Source:** to every surviving finding — the agent names and/or `orchestrator`, comma-separated, assigned from the response file each came from, never from agent text. When sources contradict each other, the cited text decides: if the finding survives, note it on the Source line (`Source: glm, kimi; codex disagrees`); if the text cannot settle it, the finding fails the drop rule.

## Coverage

The calling skill's report starts with one line per agent: usable or partial, with findings raised and how many survived verification, plus the exit for partial; or its failure class (timeout / error / empty / narration-only) with the reason. Add "after resume" when the agent was resumed, or "after relaunch" when it was launched afresh.

## Cleanup

After the report, or on any stop, stop calls still running. Keep `<dir>`: its runs stay resumable for follow-up questions to an agent, and the OS clears it.
