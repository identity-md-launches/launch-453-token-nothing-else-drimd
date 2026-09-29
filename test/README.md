# drIMD test coverage

The existing `LaunchToken.t.sol` checks metadata, fixed issuance, fee rounding,
events, overlapping accounts, unavailable administrative calls, and ERC-20 failure
paths. The additional suites exercise behavior across multiple calls:

- `LaunchTokenAdversarial.t.sol`: allowance exhaustion and renewal, approval
  replacement/revocation, spender isolation, arbitrary overlapping addresses,
  maximum delegated amounts, and rejected ETH-bearing ERC-20 calls. Its three
  fuzz properties run 1,000 cases each.
- `LaunchTokenInvariant.t.sol`: 256 sequences of 128 handler calls, mixing direct
  and delegated transfers, finite/unlimited/revoked approvals, overdraws,
  underapprovals, zero-address failures, and attempted administrative calls.
  Unexpected handler reverts fail the campaign.

The invariant ledger starts from the specified supply and changes only according
to authorized actions and the required 5% fee, rounded down to minor units.
It never copies observed token balances or allowances to establish expectations.
The invariants verify fixed supply, conservation across every reachable holder,
individual balances (including treasury fees), and all actor-pair allowances.
Expected reverts leave the ledger unchanged, checking rollback after failures.

Five actors include the deployer and fee recipient. The token contract is also a
tracked destination, but is never impersonated to withdraw its holdings. Inputs
include zero, one, fee-rounding boundaries, full balances, and oversized amounts.
The action target list excludes getters and test helper functions.

Use the existing vendored dependencies and compiler; no network or configuration
changes are needed. To keep generated files inside the task's scratch directory:

```sh
forge build --offline --out test/scratch/out --cache-path test/scratch/cache
forge test --offline --out test/scratch/out --cache-path test/scratch/cache
```

Revision verification (2026-09-29) with Foundry 1.8.3: the offline build passes, and the
existing tests pass without changes. Forge reports 40 passing tests: 39 unit/fuzz
tests and one grouped invariant campaign checking the three invariant functions
above. That campaign executes 32,768 handler calls with no unexpected reverts or
discarded calls. No concrete implementation defect or harness error was found
that would justify rewriting the accepted suites.

The supplied protected launch checks were separately run unchanged, with the
compiled token, 7 decimals, the specified supply, and zero application contracts.
Seven pass; the transfer check fails because it requires fee-free receipt.
A gross transfer of `100000000000` minor units credits `95000000000` to the
recipient and `5000000000` to the required fee address. This task/policy conflict
is reported in `../.imd-findings.json` as a medium-severity acceptance-policy
conflict, with a self-contained proof that was run and observed to fail. The
proof reproduces the protected requirement; it does not prescribe removing the
task's required fee. The standalone reproduction command was:

```sh
forge test --offline --out test/scratch/out --cache-path test/scratch/cache \
  --match-path test/scratch/LaunchPolicyConflictProof.t.sol -vvv
```

The proof source is embedded in the report's `proof` field. Both this proof and
the unchanged protected transfer check fail with
`recipient received a different amount: 95000000000 != 100000000000`.
Scratch-only failing Solidity sources were removed after recording the proof so
the delivered suite passes. The conflict requires upstream reconciliation;
the passing token tests preserve the explicit 5% fee requirement.

These local tests use no fork or deployed integration. Random sequences cover a
bounded actor set and curated administrative selectors; they do not establish
compatibility with pools or distributors that assume fee-free transfers.
