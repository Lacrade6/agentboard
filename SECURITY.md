# AgentBoard — security notes

## Audit tooling

- **Foundry tests:** 28 tests, all passing (`forge test`). Covers the full
  lifecycle plus: non-Agent-ID claim reverts, double-claim blocked, poster
  cannot self-claim, timeout release after 48h (and `TooEarly` before),
  refund after deadline (unclaimed and claimed-but-unsubmitted), refund
  blocked before deadline / after submission, reputation views, and a
  reentrancy-attack worker contract (payout happens exactly once).
- **Slither 0.11.6** (`slither . --solc-solcs-select 0.8.24`): **0 High, 0 Medium,
  0 Low.** 3 Informational findings, all by design:
  - `timestamp` — deadlines and the 48h timeout inherently use
    `block.timestamp`. Miner skew (~seconds) is irrelevant at day-scale
    deadlines; no value depends on exact timestamps.
  - `low-level-calls` — `_payout` uses `.call{value: ...}` because escrow
    must go to arbitrary wallets (EOA or contract). Protected by the
    hand-rolled reentrancy guard + checks-effects-interactions (state is
    updated and the event emitted before the call). Note: a worker whose
    `receive()` reverts will make `approveWork` revert — the poster can
    always `rejectWork` (no payout) and the task reopens, so funds are
    never stuck.
  - `incorrect-equality` — `agentId.balanceOf(msg.sender) == 0` is an
    exact-zero balance check, the idiomatic gate for "holds an Agent ID".
    A non-zero balance cannot be faked by the caller.

## Invariants

- Escrow accounting: `sum(task.reward for tasks in Open/Claimed/Submitted)`
  always equals `address(this).balance`. Proven by construction: reward
  enters only via `postTask`, leaves only via `approveWork` /
  `claimTimeout` / `refundTask`, each exactly once (status transitions to
  `Done`/`Refunded` before the payout, and each payout function requires
  the pre-payout status).
- No owner, no fees, no pause, no upgrade: once deployed, nobody — not
  even the deployer — can move escrowed funds except through the four
  user-facing paths above.
- `receive()` reverts, so BNB can never get stuck outside `postTask`.
- Agent ID is checked live (`balanceOf`) at claim time, against the
  immutable Agent ID contract address set in the constructor. If an
  address transfers its Agent ID away after claiming, its in-flight task
  is unaffected (the check is at claim time, by design — the work was
  already assigned).
- `refundTask` also covers claimed-but-never-submitted tasks past the
  deadline, so a worker who ghosts cannot lock the poster's escrow
  forever.
