# Feature request: quieter, conversational #bobiverse talk

**Date:** 2026-09-20
**Repos:**
- Protocol / DMs / parse: https://github.com/SimonBarnett/agentic_irc
  (`scripts/bobstat.py`, `scripts/irc_agent.py`, skill `bob-irc`)
- Producer / Watch: https://github.com/SimonBarnett/agentic_build
  (`Write-BobIrcStatus`, `Watch-Bobiverse`, `docs/bobiverse.md`)
**Raised by:** Simon
**UAT + hostile MRB owner:** Bob
**Related:** [agentic_build#14](https://github.com/SimonBarnett/agentic_build/pull/14) (POINT dedupe; not this UX)

Intake issue: https://github.com/SimonBarnett/agentic_build/issues/36
Open a matching `feature-request` on **agentic_irc** when a token can write
that repo.
Do not invent a new IRC verb family. Git-task verbs stay
`SPEC` `WAIT` `BUILD` `PUSH` `MRB` `FIX` `UAT`.

## Problem

`#bobiverse` is a kv firehose. Every Watch tick (~30s) wants to POINT a
full `BOB v1 id=… weekly=… reset=… cur=… running=… queued=… lastSeen=… jobs=…`
line. Humans (Halloy) and joining agents cannot read it as a conversation.
The flood also dropped Ergo (fixed on the producer in #14). The remaining
product ask is **talk**, not another compact of the same blob.

Today a joining nick gets `--hello flamingo-builder` plus whatever POINT
pile is in the channel. Nobody DMs them the current picture.

## LOCKED

1. **Less noise.** The channel is a conversation, not a telemetry dump.
2. **One piece of information per message.** Do not pack model + task +
   repo + SHA + runtime + hung into one PRIVMSG.
3. **Only when it changes.** If the field did not change, do not speak.
   A ticking `lastSeen=` is not a change. Idle boxes stay quiet.
4. **Conversational English.** A person can read the line in Halloy
   without knowing `BOB v1` keys. Example tone (not a locked template):

   > bob-ionos: still on Cursor Models, MRB of SimonBarnett/agentic_build
   > at 82a8fb2 — about 12 minutes in, still responding.

5. **Each spoken fact names enough context to stand alone:**
   - **model** (Cursor Models / grok.exe / Copilot / Grok Bot — the
     fuel actually running, not a vendor dump)
   - **task kind:** worker, MRB, or UAT (Bob is the only UAT stamp)
   - **repo** the thread is on (`owner/repo`)
   - **how long** it has been running (human: "4 minutes", "an hour")
   - **hung or responding**
   - **SHA** (short is fine)
6. **Join briefing is a DM.** When a `bob-*` (or chair-approved) nick
   JOINs `#bobiverse` or `MOOT v1 JOIN`s the fleet moot, update **that
   nick** with current status as a direct message (`PRIVMSG <nick>`),
   not another channel dump. One briefer (chair, else first sitting
   roster nick). Do not have every box whisper the same novel.
7. **`!bobiverse` command.** A nick who sends `!bobiverse` (channel
   `#bobiverse`, or a PM to a `bob-*`) gets a **direct message** of the
   current network: each sitting box, conversational, with model, kind
   (worker / MRB / UAT), repo, how long, hung/responding, SHA. Not a
   `BOB v1` kv dump. One briefer answers. The channel does not echo the
   snapshot. Case-insensitive; treat `!bobiverse` as the first token.
8. **Do not break** the tray. `bob-peers\<id>.json` and weekly bars stay
   populated. BOB v1 on-disk / parse path remains until a replacement
   parser is green. Do not break prior POINT readers in one jump.
9. **No secrets.** No `password=`, no `XAI_API_KEY`, no connect file.

## UNKNOWN

- Exact sentence templates (lock in implementation; keep them short).
- Whether leftover `MOOT v1 POINT` / `BOB v1` still hits the channel for
  the tray, or only disk + conversational talk on the wire.
- DM transport: plain IRC PRIVMSG-to-nick (preferred, readable in
  Halloy) vs SEAL (wrong — this is not a secret).
- Who writes the English: Watch (no grok.exe, no reasoning) via a
  formatter, or `irc_agent` / `bobstat` when a field flips.
- Whether a human nick (`simon`) also gets the join DM (probably yes if
  they JOIN `#bobiverse`).
- `!bobiverse` cooldown / who may query (any nick on the channel vs
  roster only). Default: any channel nick, with a short per-nick
  cooldown so it cannot flood Ergo.
- Whether the `!bobiverse` DM is one PRIVMSG or one short line per
  machine (still only to the asker).

## Alternatives (pick in implementation; recommend A)

**A — Recommended. Quiet talk + `!bobiverse` pull + keep BOB v1 off the human ear**

Watch still writes `bob-peers\<id>.json` locally. Conversational lines
go to the channel **only on a field change**, one field per line.
`BOB v1` POINT is not PRIVMSG'd every tick (file/offset is enough for
the local tray). Join = one short DM briefing. `!bobiverse` = on-demand
DM of the whole network to the asker (not `?status`, not a channel
NOTICE). Channel stays quiet otherwise.

**B — Replace BOB v1 with a talk dialect**

Channel only ever sees English. Tray learns to parse the talk lines
(or a parallel `BOB v2 talk` prefix). Bigger blast radius; breaks
today's `ConvertFrom-BobIrcPoint` / `bobstat.parse_bob_point` until
both repos move together.

**C — Channel silent except `!bobiverse` and join DM**

No change-talk on the channel at all. Status is join-DM + `!bobiverse`.
Quietest. Use if A still feels chatty.

**D — Rotate one field per tick**

Even when nothing changed, speak one rotating field every 30s. Still
periodic noise. Reject unless A proves too quiet for Halloy.

**E — Digest NOTICE every N minutes**

One paragraph if *anything* changed since last digest. Fewer messages
than A, but not "one piece at a time". Fallback if A feels chatty.

**Command reply in-channel** (rejected): answering `!bobiverse` on
`#bobiverse` puts the snapshot back on the firehose. DM only.

Do **not** suggest raising Ergo flood limits or forcing `--host
127.0.0.1`. Those are the wrong layer. Do not invent `?status` /
`!net` as a second command; the token is `!bobiverse`.

## Ask

### agentic_irc

1. `irc_agent` can `PRIVMSG` a nick (whisper). Today `say()` is channel
   only.
2. On IRC JOIN / `MOOT v1 JOIN` of a fleet nick, the briefer DMs current
   status in conversational English (from `bob-peers\` + live self).
3. On `!bobiverse` (channel or PM), the same briefer DMs **the asker**
   the current network. One answerer. Per-nick cooldown. Do not have
   four `bob-*` nicks all whisper. Do not PRIVMSG the snapshot to
   `#bobiverse`.
4. Optional helper to format one change into one short sentence
   (`bobstat` or a sibling). No new moot verb required unless A needs a
   `TALK` distinct from `POINT` — prefer reusing `SAY` in mode=free or a
   single documented prefix so Halloy stays readable.
5. Skill `bob-irc`: channel is quiet talk; join and `!bobiverse` get a
   DM; do not POINT a full blob every poll.

### agentic_build

1. `Write-BobIrcStatus` does not append a channel line unless a **named
   field** changed (model, kind, repo, sha, hung/responding, running
   job). `lastSeen` / weekly-only ticks stay on disk.
2. When it does speak: **one field**, conversational, with the LOCKED
   context (model, kind, repo, duration, hung/responding, sha) only as
   needed so the sentence stands alone — not a second kv list.
3. Populate those fields from the live job (fuel/model, `kind` worker /
   mrb / uat, `repo`, tip SHA, start time, stall/responding).
4. Tests in `Test-Pack` BT0o: no speak on lastSeen-only; one speak on
   kind/repo/sha change; no secrets.

## Acceptance

1. Idle box: no channel PRIVMSG across several Watch ticks.
2. Job starts / kind flips / SHA moves / hung↔responding: **one**
   conversational line, not a `BOB v1` dump.
3. New nick JOINs: they receive a DM briefing; the channel does not get
   a full roster dump.
4. A nick sends `!bobiverse` in `#bobiverse` (or PM): they receive a DM
   of the current network; the channel does not get the snapshot; only
   one `bob-*` answers.
5. Halloy can read the line without a spec. Tray weekly bars still
   paint.
6. Off-DEV tests (no live IRC). No `password=` in git or prompts.
7. Matching docs in `docs/bobiverse.md` and agentic_irc `bob-irc`.

## Non-goals

- New git-task verbs.
- Bob stamping UAT from IRC.
- Changing Ergo flood numbers.
- Forcing loopback host.
- SEAL / DUMB / Mode 3.
- Making Watch a grok.exe session.

## Verify on ionos / flamingo

1. Halloy on `#bobiverse`: quiet while idle; one readable line when a
   job actually changes.
2. Join a spare nick: get a DM of who is doing what, on which repo,
   which SHA, how long, hung or not — not a `BOB v1` wall.
3. From Halloy, type `!bobiverse` in `#bobiverse`: a DM arrives with the
   current network; the channel stays quiet.
4. One `irc_agent` per box; no 001/JOIN reconnect spam.
