# Insider-Resistant Blockchain Academic Credential Verification

CSCI 435 Research Track project. Topic: *Blockchain for credential verification in RK education.*

**Research question.** How do role-constrained approval policies compare with single-issuer, unanimous and
majority-based policies in insider resistance, gas consumption and issuance availability?

> Research prototype. All universities, people and credentials are **synthetic**. Nazarbayev University is a
> hypothetical case study only. It does not use this system.

## Status

| Stage | State |
|---|---|
| 1. Architecture & threat model | done: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md), [`docs/THREAT_MODEL.md`](docs/THREAT_MODEL.md) |
| 2. Registry: issue / verify / revoke | implemented: `src/CredentialRegistry.sol` |
| 3. Four approval policies | implemented: `src/policies/` |
| 4. Foundry tests | written: `test/` (to be run) |
| 5. End-to-end demo | `script/Demo.s.sol` |
| 6–9. Experiments A/B/C, figures | todo: `experiments/` |
| 10. Paper | todo: `paper/` |

## Layout

```
src/
  CredentialRegistry.sol        shared registry + lifecycle
  Types.sol                     Role enum
  interfaces/IApprovalPolicy.sol
  policies/                     A SingleIssuer, B Unanimous, C Majority, D RoleConstrained
test/
  utils/CredentialFixture.sol   synthetic NU: 2 Registrars, 3 Deans, 2 Exam Officers
  Registry.t.sol  Issuance.t.sol  Verification.t.sol  Revocation.t.sol  PolicySecurity.t.sol
script/
  Deploy.s.sol                  deploy one policy + registry
  Demo.s.sol                    full lifecycle walkthrough
experiments/  data/  figures/  paper/  docs/
```

## Setup (from a clean clone)

Requirements: Git, [Foundry](https://book.getfoundry.sh/getting-started/installation) (on Windows run
`foundryup` from Git Bash or use WSL), and Python 3.11+ (for experiments, added later).

```bash
git clone https://github.com/VeyelutD/education-credential-verification.git
cd education-credential-verification
forge install foundry-rs/forge-std@v1.9.4 OpenZeppelin/openzeppelin-contracts@v5.1.0
forge build
forge test -vv
```

Pinned versions: solc 0.8.24 (EVM `cancun`, optimizer 200 runs), OpenZeppelin Contracts v5.1.0,
forge-std v1.9.4, fuzz seed `0x435` (see `foundry.toml`).

## Demo

Dry run on Foundry's in-memory EVM, no node needed:

```bash
forge script script/Demo.s.sol -vv
```

Against a local Anvil node:

```bash
anvil
forge script script/Demo.s.sol --rpc-url http://127.0.0.1:8545 --broadcast -vv
```

The demo deploys the role-constrained policy, registers a synthetic NU with 7 employees, proposes a diploma,
collects 3 more approvals, finalizes, verifies as an employer, shows that an edited diploma fails
verification, and shows that revocation changes the result. It uses Anvil's public **test** mnemonic only.

## Gas report

```bash
forge test --gas-report
```

## Credential hashing (summary)

`commitment = keccak256(abi.encode(keccak256("KZ-ACADEMIC-CREDENTIAL-v1"), keccak256(canonicalJSON), salt))`,
where `salt` is 32 random bytes held by the graduate. Full procedure: [`docs/ARCHITECTURE.md` §3](docs/ARCHITECTURE.md).

## Reused code

- OpenZeppelin Contracts v5.1.0 (MIT): `AccessControl`.
- forge-std v1.9.4 (MIT / Apache-2.0): test and script utilities.

## License

MIT, see [`LICENSE`](LICENSE).
