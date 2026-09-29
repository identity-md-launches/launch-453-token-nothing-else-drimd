# Validation record

Checked with Foundry 1.8.3 and the configured Solidity 0.8.26 compiler.

## Delivered project

- `forge build`: passes.
- `forge test`: 34 tests pass, including three fuzz tests at 512 runs each.
- `forge fmt --check`: passes.
- Source and test review: no concrete implementation defect identified.
- Optimized token runtime: 2,151 bytes; a PUSH-aware scan of deployed bytecode
  finds no `DELEGATECALL`, `CALLCODE`, or `SELFDESTRUCT` instructions.

The production source and tests import only vendored Solidity files. No test
requires network access or environment configuration. Slither, Mythril, deployment,
and on-chain integration tests were not run.

## Supplied protected checks: incompatible transfer assertion

Both supplied test files were copied unchanged into temporary `test/scratch/`
and executed against this token's compiled creation bytecode. The test process
was configured with expected decimals `7`, expected supply `100000000000000`,
zero application contracts, and a deterministic local CREATE2 factory address.
The original input files were not modified. The temporary Solidity copies were
removed after that run; they are not part of the delivered suite.

Results: **7 passed, 1 failed, 0 skipped**.

- Project checks: 2/2 pass. The factory receives the whole fixed supply. There
  are zero application contracts, so the application-runtime loop is empty.
- Token checks: 5/6 pass, including decimals, whole-supply mint, restricted
  issuance and token runtime opcode checks.
- `TokenProtectedTest.test_transferMovesExactlyWhatItWasAsked` fails with:

```text
recipient received a different amount: 95000000000 != 100000000000
```

That check sends 10,000 DRIM and requires the recipient to receive all 10,000.
The explicit assignment instead requires 5% of every transfer to go to the fixed
fee recipient. The implemented result is 9,500 DRIM to the recipient plus 500
DRIM to the fee address, while the sender loses 10,000 and supply is unchanged.

These expectations cannot both hold. The implementation honors the explicit
token requirements; it does not special-case test callers, amounts, or the
factory. The fee-free protected check and any launch integration relying on
that rule must be reconciled with the assignment by the network before this
token can pass that launch policy. This is an outstanding acceptance/integration
conflict, not a claim that all supplied checks passed.
