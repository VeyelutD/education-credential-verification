# Threat model

## Security goal

**Insider-resistant issuance.** No set of compromised university employees
smaller than what the deployed policy requires can make the registry report
`Valid` for a credential the institution did not legitimately authorize.

Integrity (tamper detection) and revocation visibility are baseline goals that
every policy must also meet.

## Assets

1. The issued/revoked status of each commitment.
2. The binding between a commitment and its issuing university.
3. The approver set and role assignments.

## Adversaries

| ID | Adversary | Capabilities | In scope? |
|---|---|---|---|
| T1 | Single malicious or compromised employee | Full control of one approver key | Yes, main focus |
| T2 | Colluding coalition of k employees | Controls k approver keys, any roles | Yes. Experiment A enumerates all coalitions |
| T3 | External attacker | Any non-approver address; can read the chain and mempool | Yes |
| T4 | Verifier presented with a forged or edited document | Receives document + salt from a holder | Yes. Tamper detection |
| T5 | Compromised governor | Can add sock-puppet approvers, change roles, deactivate honest approvers | **Trusted** (see below) |
| T6 | Falsified source records (e.g. wrong grades entered before issuance) | Corrupts input data before the proposal exists | **Out of scope.** Blockchain cannot detect this |
| T7 | Ethereum consensus or compiler bugs | — | Out of scope |

## Assumptions

- A1. Approver keys are held by distinct individuals. One person is one key
  (no key sharing).
- A2. The governor is honest. **This matters a great deal.** A compromised
  governor can register new approver keys and satisfy any policy. In
  practice this role should itself be a multisig or timelocked governance
  contract controlled by a separate body (e.g. a ministry and the
  university). Modelling that is future work. The paper must state this
  assumption plainly.
- A3. Holders keep their salt confidential until they choose to disclose it.
- A4. Honest approvers check the off-chain record before approving (otherwise
  multi-party approval adds no assurance).

## What the contracts enforce (and the tests that check it)

| Threat | Mitigation | Test |
|---|---|---|
| Unauthorized issuance (T3) | Only active, eligible approvers can propose, approve or finalize | `Issuance.t.sol::test_OutsiderCannotProposeApproveOrFinalize` |
| Governor bypass (admin path) | Governor has no issuance function, and governor ≠ approver in both directions | `test_GovernorCannotIssue`, `Registry.t.sol::test_ApproverCannotBeGranted*` |
| Policy downgrade | Policy is `immutable` | by construction |
| Duplicate issuance | Pending, issued and revoked commitments cannot be proposed again | `test_DuplicateProposalReverts`, `test_CannotReproposeIssuedCredential`, `test_RevokedCommitmentCannotBeReissued` |
| Squatting: one insider proposes first, then cancels | Cancelling does not burn the commitment; no cancel after another approval; approvals are per round | `ProposalSquatting.t.sol` |
| Duplicate approval (vote inflation) | One counted approval per (commitment, approver, nonce) | `test_DuplicateApprovalReverts`, `test_ProposerCannotApproveAgain` |
| Approval reuse across credentials | Approvals are keyed by commitment | `test_ApprovalsAreNotReusableAcrossCredentials` |
| Deactivated / reassigned insider | Nonce invalidation, rechecked at finalize | `PolicySecurity.t.sol::test_RoleChangeInvalidatesPendingApproval`, `test_DeactivatedApprover...`, `test_ReactivationDoesNotReviveOldApproval` |
| Cross-university approval | Approver must belong to the proposal's university | `test_OtherUniversityCannotApproveOrFinalize` |
| Coalition below policy requirement (T1/T2) | Policy rule | `test_Coalitions_*` (all 127 coalitions × 4 policies) |
| Document tampering (T4) | Salted hash commitment | `Verification.t.sol::test_TamperedDocumentFails`, fuzz test |

## Known residual risks (for the Limitations section)

- **R1 Single-party revocation.** One compromised registrar can revoke genuine
  credentials. This is availability harm to the holder, not forgery. It is
  kept identical across policies on purpose.
- **R2 Governor trust** (A2 above).
- **R3 Front-running griefing.** A commitment is public once proposed. An
  insider coalition at another university could propose the same commitment
  first to block it. The verifier's issuer cross-check (ARCHITECTURE §3)
  stops this from producing a false `Valid` for the wrong issuer, but it
  still denies service.
- **R3b Repeated front-running.** An insider can keep proposing and cancelling
  before an honest employee approves. Each attempt costs the insider gas and is
  logged under their address, and one honest approval ends it.
- **R4 Stale pending proposals.** There is no expiry. A pending proposal
  stays until it is finalized or cancelled. Adding an expiry is possible
  future work, with its own trade-offs.
- **R5 Garbage in.** The system proves *who authorized* a commitment, not
  that the underlying academic record is true (T6).
- **R6 Metadata leakage.** Approver addresses and timestamps are public. They
  reveal issuance volume and timing per university.
- **R7 Coalition success fraction ≠ probability of fraud.** It is the share
  of k-subsets that can issue. It becomes a probability only under an
  explicit compromise model (e.g. every employee compromised independently
  with probability p).
