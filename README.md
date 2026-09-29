# drIMD (DRIM)

A single, non-upgradeable fee-on-transfer token, implemented as
`src/LaunchToken.sol:LaunchToken`. No application contracts or services are required.

## Parameters and assumptions

| Parameter | Value |
| --- | --- |
| Name / symbol | `drIMD` / `DRIM` |
| Decimals | `7` (one DRIM = `10_000_000` minor units) |
| Fixed supply | `10_000_000` DRIM = `100_000_000_000_000` minor units |
| Initial holder | Constructor caller (`msg.sender`), including a deploying factory |
| Transfer fee | 5% deducted from the gross amount, rounded down in minor units |
| Permanent fee recipient | `0x20a2Fb1bb9e6C1443C11703cCecB3685cd99b7C5` |
| Constructor arguments / value | None / zero |
| Compiler / EVM target | Solidity `0.8.26` / `paris` |

The explicit token brief determines supply, decimals, and fees. The generic
reference's billion-token, 18-decimal, fee-free template does not describe this
token. The final phrase “Testing or maybe not / DrIMD knows” supplies no additional
deterministic contract behavior; meaningful tests are included as required.

## Transfer semantics

For a gross amount `a` in minor units, `fee = floor(a / 20)` and `net = a - fee`.
The sender must have at least `a` available. An ordinary transfer of 100 DRIM
debits 100 DRIM, credits 95 DRIM to the recipient and 5 DRIM to the fee address.
The fee is neither burned nor minted; total supply remains fixed.

Both `transfer` and `transferFrom` apply the same fee. A delegated transfer
consumes the **gross** allowance; a maximum `uint256` allowance remains unlimited
following OpenZeppelin ERC-20 behavior. Zero-value transfers succeed between
valid addresses and emit a zero-value `Transfer`. Zero-address recipients and
zero-address approval spenders are rejected. Invalid transfers revert atomically,
including any allowance or fee changes.

Fees below one minor unit round to zero: transfers of 0–19 minor units incur no
fee, 20 incurs one, and 39 also incurs one. Fractional fee dust stays with the
recipient, and splitting a transfer can reduce the aggregate fee. There is no
minimum fee or accumulated fractional-fee accounting.

There are no transfer exemptions. Address overlaps combine the same ledger
entries: a self-transfer costs the sender the fee; a transfer to the fee address
credits it the entire gross amount; a transfer from the fee address returns its
fee to itself and debits only the net amount. A self-transfer by the fee address
leaves its balance unchanged. All these cases still require gross balance and,
for `transferFrom`, gross allowance.

A positive fee emits `Transfer(sender, feeRecipient, fee)` first, followed by
`Transfer(sender, recipient, net)`. The fee credit is an internal balance update,
not another taxable transfer. No external call or receiver callback occurs, so
the fee recipient cannot reject transfers. Constructor issuance emits the usual
mint event, gives the entire supply to the deployer, and is not taxed.

## Build and test

With Foundry installed and Solidity 0.8.26 available:

```sh
forge build
forge test
forge fmt --check
```

All dependency sources and licences are included in `lib/`; see
[DEPENDENCIES.md](DEPENDENCIES.md) for pinned versions and archive hashes. Imports
resolve without network access. Tests use no environment variables, RPCs, wallet
keys, FFI, or filesystem cheatcodes. Each test deploys fresh state, so test order
and parallel execution do not affect results.

Coverage includes metadata and initial supply, fee and event accounting, finite
and unlimited approvals, delegated transfers, zero and rounding boundaries,
overlapping addresses, insufficient balances and allowances, atomic rollback,
and unavailable administrative selectors. Fuzz tests check accounting and supply
conservation. See [VALIDATION.md](VALIDATION.md) for recorded results and the
provided protected-check incompatibility.

## Deployment and responsibilities

Deploy the creation bytecode for `LaunchToken` with no constructor arguments and
no ETH. The artifact is `out/LaunchToken.sol/LaunchToken.json`; its creation code
can also be inspected using `forge inspect src/LaunchToken.sol:LaunchToken bytecode`.
No script, initializer, signing key, transaction, or chain-specific deployment is
included in this assignment. Select the target chain separately; it must support
the configured EVM target.

The deploying EOA or factory receives all tokens. If a factory deploys it, that
factory must support distributing the supply using these fee semantics. Verify
name, symbol, decimals, fixed supply, initial holder, fee recipient, and source
bytecode before distribution. Deployment tooling must use the actual 7 decimals
and `100_000_000_000_000` minor-unit supply.

There is no owner or operator role: nobody can mint after construction, burn,
pause, blocklist, change the fee or recipient, upgrade, or recover assets. The
fee address has ordinary holder permissions only. Whoever controls it manages
its collected tokens; ownership or control of that address has not been verified.
Tokens transferred to this token contract itself cannot be recovered through it.

Integrations must account for net received balances. A factory, pool, distributor,
or exchange that assumes transfers deliver the stated gross amount is incompatible
unless explicitly designed for transfer fees. The supplied launch-token floor
contains precisely such an assumption, documented in VALIDATION.md. Deployment
must resolve that integration conflict; this implementation has no hidden
fee-exemption switches to bypass it.

No keeper, scheduler, oracle, or ongoing maintenance transaction is needed. The
deployer is responsible for chain selection, source verification, distribution
and integration review. Local tests and source review are not an independent
production security audit; release review remains a deployment responsibility.
