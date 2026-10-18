# Personal guidelines (all projects)

- Report every time in my timezone, America/New_York, with UTC in parentheses, e.g. `11:42 PM EDT, Oct 17 (03:42 UTC Oct 18)`. Convert tool output (usually UTC) before writing it, check the EDT/EST offset for the date, and pair relative waits ("in about 50 minutes") with the clock time.
- Run long waits and loops (review loops, CI waits, deploys) directly as their own tracked background commands, never through a launcher that detaches them. A completion notice that names a launcher or wrapper is not the result: confirm with the process list and the log tail.
- Never say "I'll check when it finishes" without a mechanism that will wake you: a tracked background command, or a timer you re-arm. A background command can be killed at the harness cap (about 10 minutes), so chunk long waits and check the clock when each chunk ends.
- When a review loop exits non-zero with pending feedback (for example `wait-for-agent-review` exit 3), triage it immediately: fix or decline, reply on the thread, resolve, push.
