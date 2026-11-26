# Architecture

Research prototype. Synthetic data only. Not a production system.

## 1. Components

```
                 governor (e.g. ministry / consortium account)
                    │  registerUniversity, addApprover,
                    │  changeApproverRole, setApproverActive,
                    │  setUniversityActive, cancel, revoke
                    ▼
┌─────────────────────────────────────────────┐      isEligible(role)
│ CredentialRegistry  (one deployment/policy) │ ───────────────────────► IApprovalPolicy
│  universities, approvers, role counts       │      isSatisfied(counts,  ├─ SingleIssuerPolicy   (A)
│  records (commitment → status)              │        total, N)          ├─ UnanimousPolicy      (B)
│  approvals (commitment, approver, nonce)    │ ◄─────────────────────── ├─ MajorityPolicy(M)    (C)
└─────────────────────────────────────────────┘                          └─ RoleConstrainedPolicy(M, mins) (D)
        ▲ propose / approve / finalize / revoke          ▲ verify / verifyDocument (free view calls)
   university employees (approvers)                  employer / verifier
```

- `src/CredentialRegistry.sol` holds all state and the whole lifecycle.
- `src/policies/*.sol` are stateless rules. The registry asks a policy two
  questions: may this role take part, and do these valid approvals authorize
  issuance? Formats, storage, events and lifecycle are the same for every
  policy, so only the authorization rule changes between experiments.
- The policy address is `immutable`. It is fixed at deployment, so no
  administrative action can switch a deployment to a weaker policy.

Reused code: OpenZeppelin Contracts v5.1.0 `AccessControl` (MIT) for the
governor role, and forge-std v1.9.4 (MIT/Apache-2.0) for tests and scripts.
Everything else in `src/` is project code.

## 2. Actors and roles

| Actor | On-chain identity | Powers |
|---|---|---|
| Governor | `GOVERNOR_ROLE` (+ `DEFAULT_ADMIN_ROLE`) | Registers universities, manages approvers and roles, (de)activates universities, cancels pending proposals, revokes credentials. **It cannot propose, approve or finalize.** |
| Registrar / Dean / Exam Officer | Registered approver, one role | Propose, approve and finalize if the policy makes their role eligible. Registrars can also revoke their university's credentials. |
| Verifier (employer) | Any address, or none (view call) | `verify`, `verifyDocument`. |
| Holder (graduate) | Off-chain | Keeps the document and salt, and discloses both to a verifier. |

Static separation of duty: an address holds exactly one approver role at one
university, and it can never also be governor. Both directions are enforced:
`addApprover` rejects governors, and the `_grantRole` override rejects
approvers.

## 3. Credential commitment (exact procedure)

1. **Canonical document.** Encode the credential as UTF-8 JSON with keys
   sorted lexicographically, no insignificant whitespace (`separators=(",", ":")`),
   and no trailing newline. The document must include the issuer identifier
   (e.g. `"issuer":"NU-SYNTHETIC"`) so verifiers can cross-check it.
2. **Document hash.** `documentHash = keccak256(canonicalBytes)`.
3. **Salt.** 32 bytes from a CSPRNG, generated once per credential and given
   to the holder. Without it, an observer could confirm guesses about
   low-entropy fields (name, degree, year) against on-chain commitments.
4. **Commitment.**
   `commitment = keccak256(abi.encode(COMMITMENT_DOMAIN, documentHash, salt))`
   with `COMMITMENT_DOMAIN = keccak256("KZ-ACADEMIC-CREDENTIAL-v1")`.
   `abi.encode` uses fixed 32-byte words, so the encoding cannot be ambiguous.
   The domain tag keeps these commitments separate from other hashes of the
   same data. `CredentialRegistry.computeCommitment` implements exactly this.
5. **On-chain** the registry stores only: commitment, status, universityId,
   proposer, timestamps, approver addresses, and a revocation reason code.
   It stores no names, IDs, grades or documents.

**Verification.** The verifier receives the document and salt from the holder
and then:
1. canonicalizes the document and computes `documentHash`;
2. calls `verifyDocument(documentHash, salt)`, or computes the commitment
   locally and calls `verify`;
3. accepts only if `status == Valid`, **and** the returned `universityId`
   maps to the university named in the document, **and** `issuerActive` meets
   the verifier's own policy.

Any change to the document or salt gives a different commitment, which
returns `NotFound`.

## 4. Lifecycle and statuses

```
            propose            finalize (policy satisfied)          revoke
  None ───────────────► Pending ──────────────────────────► Issued ─────────► Revoked
                           │
                           │ cancelProposal (proposer or governor)
                           ▼
                       Cancelled   (may be re-proposed in a new round, with no approvals)
```

`verify` maps the internal state to what the verifier sees:
`None/Cancelled → NotFound`, `Pending → Pending`, `Issued → Valid`,
`Revoked → Revoked`.

- `propose` also records the proposer's approval.
- `finalize` can be called by any eligible, active approver of the issuing
  university. It is a separate transaction so that gas can be measured per
  step.
- A commitment can be issued at most once. A revoked credential is re-issued
  under a new salt, so it gets a new commitment.
- Cancelling starts a new round: approvals are keyed by (commitment, round), so
  none carry over. A proposer can cancel only while nobody else has approved;
  the governor can cancel at any time. An earlier version burned cancelled
  commitments, which let one insider block a credential permanently.

## 5. Pending proposals when approvers change

Each approver has a `nonce`. It starts at 1 and increases on **every** role
change, deactivation or reactivation. An approval stores the approver's nonce
at the time it was given. At `finalize`, an approval counts only if:

- the approver is still active,
- their nonce has not changed since they approved, and
- their current role is eligible under the policy.

Consequences:

| Event while a proposal is pending | Effect |
|---|---|
| Approver deactivated | Their approval stops counting. Reactivation does **not** restore it. |
| Approver role changed | Their approval stops counting. They may approve again, and the new approval counts under the new role. |
| New approver added | Under Unanimous, N grows and the newcomer must approve. No effect on the other policies. |
| Approver deactivated (Unanimous) | N shrinks. This is a governor power, listed in the threat model. |
| University deactivated | No new propose, approve or finalize. Issued credentials keep their status, and verifiers see `issuerActive = false`. |

Approvals are keyed by commitment, so an approval for one credential never
counts for another.

## 6. Policies (primary experiment configuration)

University: 2 Registrars, 3 Deans, 2 Exam Officers (N = 7).

| Policy | Eligible roles | Rule at finalization |
|---|---|---|
| A Single issuer | Registrar | ≥ 1 valid approval (the proposer) |
| B Unanimous | all | valid approvals = all N active approvers |
| C Majority | all | ≥ 4 valid approvals, any roles |
| D Role-constrained | all | ≥ 4 valid approvals **and** ≥ 1 Registrar, ≥ 1 Dean, ≥ 1 Exam Officer |

C and D use the same threshold (4). The only difference between them is the
role constraint, so comparing them isolates its effect.

## 7. Revocation

Revocation is the same under every policy. An active Registrar of the issuing
university, or the governor, can revoke. It is a single-party action by
design, so that only issuance authorization varies between policies. This is
a known limitation: a single compromised registrar can revoke a genuine
credential (a denial-of-service on the holder, not a forgery). See
THREAT_MODEL.md.

## 8. Gas-bounding decisions

- `MAX_APPROVERS_PER_UNIVERSITY = 32` bounds the tally loop in `finalize`.
- The `Approver` struct fits in one storage slot.
- The policy is called once per role (3 calls) per tally, not once per
  approval.
