# SecureVault

A multi-user Ether custody contract built around defensive design. Every decision—from error handling to withdrawal ordering—prioritizes correctness and resistance to known attack vectors over feature richness.

---

## 1. Project Overview

On-chain custody is a solved problem only when implemented carefully. Most vulnerabilities in DeFi history trace back to a small set of well-understood mistakes: unchecked external calls, missing access control, and implicit trust in caller state. SecureVault exists to demonstrate what a minimal, production-oriented custody contract looks like when those mistakes are treated as design constraints rather than afterthoughts.

**Problem addressed:** Users need a contract that holds ETH on their behalf, enforces per-user accounting, and cannot be drained by a malicious caller—even one who controls a smart contract.

**Core design principle:** Security is not a feature to be added later. The invariants (balance integrity, authorized-only control, bounded deposits) are enforced at every entry point before any state mutation occurs.

**Target use case:** Internal treasury management, escrow primitives, or as a reference implementation for teams building custody logic on top of EVM chains.

---

## 2. Threat Model

### Attacker Capabilities

- Can deploy arbitrary smart contracts with fallback/receive logic.
- Can call any public function in any order, with any calldata.
- Can monitor the mempool and craft transactions with precise timing.
- Does **not** control the admin key (assumed secure out-of-band).
- Does **not** have the ability to reorder blocks or execute flash loan attacks that persist state across transactions in isolation.

### Key Risks Considered

| Risk                                 | Mitigation                                       |
| ------------------------------------ | ------------------------------------------------ |
| Reentrancy via malicious `receive()` | `nonReentrant` guard + CEI pattern in `withdraw` |
| Unauthorized pause/unpause           | `admin`-only check on both control functions     |
| Deposit griefing / dust flooding     | `ZeroDeposit` and `NotPermitidBalance` guards    |
| Silent transfer failure              | Return value of `.call` explicitly checked       |
| Unlimited ETH accumulation           | `maxBalance` cap enforced at deposit time        |
| Emergency without kill switch        | Pause mechanism halts deposits system-wide       |

### Explicit Assumptions

- The `admin` address is an EOA or a multisig; it is **not** a contract with reentrant capabilities.
- `maxBalance` is set at deploy time and is not adjustable. Upgrading this value requires redeployment (intentional—see §4).
- This contract does not account for ETH sent via `selfdestruct` or coinbase rewards. `address(this).balance` may exceed the sum of all user balances in edge cases.

---

## 3. Security Architecture

### Checks-Effects-Interactions (CEI)

`withdraw` follows CEI strictly. The balance is decremented **before** the external call is made:

```solidity
balance[msg.sender] -= amount_;   // Effect
(bool success, ) = msg.sender.call{value: amount_}("");  // Interaction
if (success == false) revert TransferFailed();
```

Even without `nonReentrant`, the balance update prevents a reentering caller from withdrawing more than their recorded balance. The guard is an additional layer, not a replacement for correct ordering.

### ReentrancyGuard

OpenZeppelin's `ReentrancyGuard` is applied to `withdraw` as defense-in-depth. It blocks any reentrant call at the mutex level regardless of whether CEI is violated in a future refactor. This is a deliberate redundancy: if CEI ordering is accidentally broken during maintenance, the guard still protects the invariant.

### Custom Errors and Gas Efficiency

Solidity custom errors (`error InsufficientBalance()`, etc.) encode to a 4-byte selector instead of a full string. This reduces revert gas cost and deployment size. All revert conditions use custom errors. `require` with string messages is not used anywhere in this contract.

### Pause Mechanism

The pause is a break-glass emergency control. It halts all new deposits when `IsPaused == true`. It does **not** halt withdrawals—users must always be able to recover their funds. This is a deliberate asymmetry. Activating pause signals that something has gone wrong with the deposit path (oracle failure, discovered vulnerability, regulatory event) and new capital should not enter until resolution.

Pause and unpause are admin-only and emit events for off-chain monitoring.

### Event Indexing Strategy

Both `depositEvent` and `withdrawEvent` index the `user` address. This allows off-chain indexers to efficiently filter all activity for a given account using a bloom filter lookup rather than scanning all logs. The `emergencyPause` event indexes `triggeredBy` for audit trail purposes. Amount fields are left unindexed—they are not used as filter keys and indexing them would waste gas.

---

## 4. Design Decisions & Trade-offs

### What Was Intentionally Not Implemented

**No withdrawal limit per transaction.** Adding rate limiting introduces complexity and state without a proportional security gain given the existing per-user balance accounting.

**No fee mechanism.** Out of scope. Fees introduce economic attack surfaces (front-running, fee-on-transfer token confusion) that are irrelevant to the custody primitive.

**No `receive()` or `fallback()`.** ETH can only enter through `deposit()`. This prevents accidental ETH credit without user intent and makes the accounting model unambiguous.

**No on-chain upgradeability.** Proxy patterns introduce storage collision risk and delegatecall attack surface. The contract's scope is narrow enough that redeployment is preferable to proxy complexity. Upgradeability is listed in the roadmap as an evaluation item, not a committed feature.

### Gas vs Security

`nonReentrant` adds ~2,300 gas per `withdraw` call (two SSTORE operations for the mutex). This cost is accepted unconditionally. No gas optimization will be applied that weakens the reentrancy guarantee.

`maxBalance` is checked at deposit time rather than tracking a rolling total. This means the cap applies per-transaction, not to the aggregate contract balance. A more conservative implementation would track total deposits. The current approach is simpler and sufficient for the stated use case, but this distinction should be documented in any audit.

### Centralization vs Decentralization

The `admin` role is a single address. This is an acknowledged centralization risk. The admin can halt deposits indefinitely, which is a griefing vector if the admin key is compromised. Migration to a multisig or on-chain governance is listed in the roadmap. The current design prioritizes operational simplicity for a v1 scope.

---

## 5. Roadmap

**Role-Based Access Control**
Replace the single `admin` address with OpenZeppelin's `AccessControl`. Define at minimum `PAUSER_ROLE` and `ADMIN_ROLE` as separate concerns. This reduces blast radius if a role key is compromised.

**Governance Model**
Evaluate time-locked admin actions via `TimelockController`. Pause should remain instant (emergency), but parameter changes (e.g., `maxBalance` if made mutable) should require a delay and potentially a multisig quorum.

**Upgradeability Evaluation**
Assess UUPS vs Transparent Proxy patterns. UUPS is preferred for lower runtime overhead, but requires the upgrade logic to live in the implementation contract—introducing risk if the implementation is bricked. A formal decision with documented trade-offs should precede any proxy adoption. The null option (no upgradeability, versioned redeployments) remains on the table.

**Testing and Auditing Plan**

- Achieve 100% branch coverage via Hardhat + Mocha unit tests before any mainnet consideration.
- Run Slither and Mythril static analysis; resolve all high/medium findings.
- Commission a third-party audit focused on the reentrancy surface, access control, and arithmetic edge cases.
- Formal verification of the balance invariant (`sum(balance[i]) <= address(this).balance`) is a stretch goal.

---

## 6. Testing Strategy

### Unit Tests

Each public function is tested in isolation: `deposit`, `withdraw`, `pause`, `unPause`. Tests verify correct state transitions, correct event emission, and correct revert conditions for every custom error.

### Edge Cases

- Deposit exactly at `maxBalance` (should succeed).
- Deposit one wei above `maxBalance` (should revert with `NotPermitidBalance`).
- Withdraw exact balance (should succeed and zero the mapping).
- Withdraw zero (should revert with `InsufficientBalance`—balance check fails before transfer).
- Call `pause` and `unPause` from non-admin (should revert with `NotAuthorized`).
- Deposit while paused (should revert with `EmergencyPauseError`).

### Reentrancy Attack Simulation

A dedicated attacker contract is deployed with a `receive()` function that calls back into `withdraw`. The test asserts that the second call reverts via `nonReentrant` and that the attacker's balance is correctly reduced by only one withdrawal amount. Both the CEI ordering and the mutex are validated independently by temporarily commenting out each protection in separate test branches.

### Failure Mode Testing

- Force `TransferFailed` by using a contract with a reverting `receive()` as the withdrawer.
- Verify that balance is restored on `TransferFailed` (it is not in the current implementation—state is mutated before the failed call; this is a known trade-off with CEI and should be explicitly tested and documented).

---

## 7. Lessons Learned

**CEI is not optional.** The mental model of "I'll add a reentrancy guard so I don't need to think about ordering" is wrong. Guards fail silently in some delegatecall contexts and can be removed by a future developer who doesn't understand why they're there. CEI enforces the invariant at the language level.

**Custom errors are strictly better than require strings.** There is no situation in Solidity 0.8+ where `require(condition, "string")` is preferable. The gas savings are real, the selector-based decoding is supported by all major tooling, and the ergonomics are equivalent.

**The pause asymmetry (halt deposits, allow withdrawals) is a design principle, not an oversight.** Any emergency mechanism that can trap user funds is a protocol liability. If the pause also blocked withdrawals, a compromised admin key becomes a theft vector, not just a griefing vector.

**Implicit ETH accounting is dangerous.** Not implementing `receive()` is an active decision. If ETH can enter through multiple paths (direct transfer, `selfdestruct`, coinbase), the invariant `sum(balance[i]) == address(this).balance` becomes impossible to maintain. Restricting entry to a single explicit function makes the accounting model auditable.

**Redundant protections compound.** `nonReentrant` and CEI together mean an attacker must defeat both simultaneously. This is the correct posture for custody contracts: assume any individual defense can fail and design accordingly.

---

## License

MIT
