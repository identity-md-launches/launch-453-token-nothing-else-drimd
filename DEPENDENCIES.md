# Vendored dependencies

All imported Solidity sources and their licences are ordinary files under `lib/`.
No submodules, package manager, or network are needed to resolve imports.

| Dependency | Pinned release | Included files | Release archive SHA-256 |
| --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2) | v5.0.2 | ERC20 and its complete import closure, MIT licence | `18c7b7e949b9a82dcd8cd394426c9c2636dfc263aa2317d4749dbfa0c7b3925a` |
| [forge-std](https://github.com/foundry-rs/forge-std/tree/v1.9.7) | v1.9.7 | `src/`, MIT and Apache-2.0 licences | `45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94` |

Archives were downloaded from `https://codeload.github.com/<repository>/tar.gz/refs/tags/<release>`.
The Solidity sources are unmodified upstream files. forge-std is a test-only dependency.
Foundry and Solidity 0.8.26 are build tools supplied by the execution environment;
compiler executables are intentionally not vendored.
