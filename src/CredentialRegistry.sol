// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IApprovalPolicy} from "./interfaces/IApprovalPolicy.sol";
import {Role, ROLE_SLOTS} from "./Types.sol";

/// @title CredentialRegistry
/// @notice Shared registry for issuing, verifying and revoking academic
///         credential commitments under a pluggable approval policy.
/// @dev Design summary (see docs/ARCHITECTURE.md for the full rationale):
///  - Only a salted commitment of each credential is stored on-chain. Personal
///    data and documents stay off-chain.
///  - The approval policy is fixed at deployment (`immutable`). Nobody,
///    including the governor, can swap it for a weaker one later.
///  - The governor manages universities and approvers but holds no issuance
///    power: it cannot propose, approve or finalize, and an address can never
///    be both governor and approver.
///  - Each approval is bound to (commitment, approver, approver nonce). Any
///    role change or (de/re)activation bumps the approver's nonce, which
///    invalidates every approval they gave on still-pending proposals.
contract CredentialRegistry is AccessControl {
    // ---------------------------------------------------------------------
    // Constants
    // ---------------------------------------------------------------------

    /// @notice Role allowed to register universities and manage approvers.
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    /// @notice Domain-separation tag mixed into every commitment.
    bytes32 public constant COMMITMENT_DOMAIN = keccak256("KZ-ACADEMIC-CREDENTIAL-v1");

    /// @notice Upper bound on approvers per university; bounds the gas of
    ///         the tally loop in `finalize`.
    uint256 public constant MAX_APPROVERS_PER_UNIVERSITY = 32;

    // ---------------------------------------------------------------------
    // Types
    // ---------------------------------------------------------------------

    /// @dev Internal lifecycle state of a commitment. `Cancelled` commitments
    ///      are burned: they can never be proposed again.
    enum RecordStatus {
        None,
        Pending,
        Issued,
        Revoked,
        Cancelled
    }

    /// @notice What a verifier is told about a commitment.
    enum VerificationStatus {
        NotFound,
        Pending,
        Valid,
        Revoked
    }

    struct University {
        bool exists;
        bool active;
        uint16 approverCount;
        string name;
    }

    /// @dev Packs into one storage slot. `nonce == 0` means "never registered".
    struct Approver {
        uint32 universityId;
        Role role;
        bool active;
        uint64 nonce;
    }

    struct Record {
        RecordStatus status;
        uint32 universityId;
        uint64 proposedAt;
        uint64 issuedAt;
        uint64 revokedAt;
        address proposer;
        bytes32 revocationReason;
    }

    struct VerificationResult {
        VerificationStatus status;
        uint32 universityId;
        bool issuerActive;
        uint64 issuedAt;
        uint64 revokedAt;
        bytes32 revocationReason;
    }

    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------

    IApprovalPolicy public immutable policy;

    uint32 public universityCount;

    mapping(uint32 universityId => University) private _universities;
    /// @dev Active approvers per role, indexed by uint8(Role).
    mapping(uint32 universityId => uint256[4]) private _activeRoleCount;
    mapping(address account => Approver) private _approvers;

    mapping(bytes32 commitment => Record) private _records;
    /// @dev Distinct addresses that have ever approved this commitment.
    mapping(bytes32 commitment => address[]) private _approvalList;
    /// @dev Approver nonce at the time of approval (0 = never approved).
    mapping(bytes32 commitment => mapping(address approver => uint64 nonce)) private _approvalNonce;

    // ---------------------------------------------------------------------
    // Events (audit trail)
    // ---------------------------------------------------------------------

    event UniversityRegistered(uint32 indexed universityId, string name);
    event UniversityStatusChanged(uint32 indexed universityId, bool active);
    event ApproverAdded(uint32 indexed universityId, address indexed account, Role role);
    event ApproverRoleChanged(uint32 indexed universityId, address indexed account, Role oldRole, Role newRole);
    event ApproverStatusChanged(uint32 indexed universityId, address indexed account, bool active);
    event CredentialProposed(bytes32 indexed commitment, uint32 indexed universityId, address indexed proposer);
    event CredentialApproved(bytes32 indexed commitment, address indexed approver, Role role);
    event ProposalCancelled(bytes32 indexed commitment, address indexed by);
    event CredentialIssued(
        bytes32 indexed commitment, uint32 indexed universityId, address indexed finalizer, uint256 validApprovals
    );
    event CredentialRevoked(bytes32 indexed commitment, uint32 indexed universityId, address indexed by, bytes32 reason);

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    error ZeroAddress();
    error UnknownUniversity(uint32 universityId);
    error UniversityInactive(uint32 universityId);
    error InvalidRole();
    error ApproverAlreadyRegistered(address account);
    error ApproverNotRegistered(address account);
    error GovernorCannotBeApprover(address account);
    error TooManyApprovers(uint32 universityId);
    error NoStateChange();
    error NotActiveApprover(address account);
    error NotEligible(address account, Role role);
    error WrongUniversity(address account, uint32 universityId);
    error InvalidCommitment();
    error CommitmentAlreadyUsed(bytes32 commitment, RecordStatus status);
    error NotPending(bytes32 commitment);
    error AlreadyApproved(bytes32 commitment, address approver);
    error PolicyNotSatisfied(bytes32 commitment);
    error NotIssued(bytes32 commitment);
    error NotAuthorizedToRevoke(address account);
    error NotAuthorizedToCancel(address account);

    // ---------------------------------------------------------------------
    // Construction
    // ---------------------------------------------------------------------

    constructor(IApprovalPolicy policy_, address governor) {
        if (address(policy_) == address(0) || governor == address(0)) revert ZeroAddress();
        policy = policy_;
        _grantRole(DEFAULT_ADMIN_ROLE, governor);
        _grantRole(GOVERNOR_ROLE, governor);
    }

    // ---------------------------------------------------------------------
    // Governance: universities and approvers
    // ---------------------------------------------------------------------

    function registerUniversity(string calldata name) external onlyRole(GOVERNOR_ROLE) returns (uint32 universityId) {
        universityId = ++universityCount;
        University storage u = _universities[universityId];
        u.exists = true;
        u.active = true;
        u.name = name;
        emit UniversityRegistered(universityId, name);
    }

    /// @notice Deactivating a university blocks new proposals, approvals and
    ///         finalizations. Already-issued credentials keep their status;
    ///         verifiers see `issuerActive == false`.
    function setUniversityActive(uint32 universityId, bool active) external onlyRole(GOVERNOR_ROLE) {
        University storage u = _requireUniversity(universityId);
        if (u.active == active) revert NoStateChange();
        u.active = active;
        emit UniversityStatusChanged(universityId, active);
    }

    /// @notice Register `account` as an approver with exactly one role.
    /// @dev An address is bound to one university and one role at a time
    ///      (static separation of duty). It can never be re-registered.
    function addApprover(uint32 universityId, address account, Role role) external onlyRole(GOVERNOR_ROLE) {
        University storage u = _requireUniversity(universityId);
        if (account == address(0)) revert ZeroAddress();
        if (role == Role.None) revert InvalidRole();
        if (_approvers[account].nonce != 0) revert ApproverAlreadyRegistered(account);
        if (hasRole(GOVERNOR_ROLE, account) || hasRole(DEFAULT_ADMIN_ROLE, account)) {
            revert GovernorCannotBeApprover(account);
        }
        if (u.approverCount >= MAX_APPROVERS_PER_UNIVERSITY) revert TooManyApprovers(universityId);

        u.approverCount += 1;
        _approvers[account] = Approver({universityId: universityId, role: role, active: true, nonce: 1});
        _activeRoleCount[universityId][uint8(role)] += 1;
        emit ApproverAdded(universityId, account, role);
    }

    /// @notice Change an approver's role. Invalidates all of their approvals
    ///         on pending proposals (they may re-approve under the new role).
    function changeApproverRole(address account, Role newRole) external onlyRole(GOVERNOR_ROLE) {
        Approver storage ap = _requireApprover(account);
        if (newRole == Role.None) revert InvalidRole();
        Role oldRole = ap.role;
        if (oldRole == newRole) revert NoStateChange();

        if (ap.active) {
            _activeRoleCount[ap.universityId][uint8(oldRole)] -= 1;
            _activeRoleCount[ap.universityId][uint8(newRole)] += 1;
        }
        ap.role = newRole;
        ap.nonce += 1;
        emit ApproverRoleChanged(ap.universityId, account, oldRole, newRole);
    }

    /// @notice Disable or re-enable an approver. Either direction bumps the
    ///         nonce, so approvals given before a deactivation never revive.
    function setApproverActive(address account, bool active) external onlyRole(GOVERNOR_ROLE) {
        Approver storage ap = _requireApprover(account);
        if (ap.active == active) revert NoStateChange();

        if (active) {
            _activeRoleCount[ap.universityId][uint8(ap.role)] += 1;
        } else {
            _activeRoleCount[ap.universityId][uint8(ap.role)] -= 1;
        }
        ap.active = active;
        ap.nonce += 1;
        emit ApproverStatusChanged(ap.universityId, account, active);
    }

    /// @dev Block granting governor/admin powers to an approver, so that the
    ///      "governor holds no issuance power" invariant cannot be bypassed.
    function _grantRole(bytes32 role, address account) internal override returns (bool) {
        if ((role == GOVERNOR_ROLE || role == DEFAULT_ADMIN_ROLE) && _approvers[account].nonce != 0) {
            revert GovernorCannotBeApprover(account);
        }
        return super._grantRole(role, account);
    }

    // ---------------------------------------------------------------------
    // Issuance lifecycle
    // ---------------------------------------------------------------------

    /// @notice Open an issuance proposal. The proposal itself counts as the
    ///         proposer's approval.
    function propose(bytes32 commitment) external {
        if (commitment == bytes32(0)) revert InvalidCommitment();
        Record storage rec = _records[commitment];
        if (rec.status != RecordStatus.None) revert CommitmentAlreadyUsed(commitment, rec.status);

        Approver memory ap = _requireEligible(msg.sender);

        rec.status = RecordStatus.Pending;
        rec.universityId = ap.universityId;
        rec.proposedAt = uint64(block.timestamp);
        rec.proposer = msg.sender;
        emit CredentialProposed(commitment, ap.universityId, msg.sender);

        _recordApproval(commitment, msg.sender, ap);
    }

    /// @notice Approve a pending proposal of your own university.
    function approve(bytes32 commitment) external {
        Record storage rec = _requirePending(commitment);
        Approver memory ap = _requireEligible(msg.sender);
        if (ap.universityId != rec.universityId) revert WrongUniversity(msg.sender, rec.universityId);

        uint64 given = _approvalNonce[commitment][msg.sender];
        if (given != 0 && given == ap.nonce) revert AlreadyApproved(commitment, msg.sender);

        _recordApproval(commitment, msg.sender, ap);
    }

    /// @notice Issue the credential if the policy is satisfied by the
    ///         approvals that are *still valid now*.
    function finalize(bytes32 commitment) external {
        Record storage rec = _requirePending(commitment);
        Approver memory ap = _requireEligible(msg.sender);
        if (ap.universityId != rec.universityId) revert WrongUniversity(msg.sender, rec.universityId);

        (uint256[4] memory counts, uint256 total, uint256 eligibleActive) = _tally(commitment, rec.universityId);
        if (!policy.isSatisfied(counts, total, eligibleActive)) revert PolicyNotSatisfied(commitment);

        rec.status = RecordStatus.Issued;
        rec.issuedAt = uint64(block.timestamp);
        emit CredentialIssued(commitment, rec.universityId, msg.sender, total);
    }

    /// @notice Withdraw a pending proposal. Allowed for the (still active)
    ///         proposer or the governor. The commitment is burned.
    function cancelProposal(bytes32 commitment) external {
        Record storage rec = _requirePending(commitment);
        bool isProposer = msg.sender == rec.proposer && _approvers[msg.sender].active;
        if (!isProposer && !hasRole(GOVERNOR_ROLE, msg.sender)) revert NotAuthorizedToCancel(msg.sender);

        rec.status = RecordStatus.Cancelled;
        emit ProposalCancelled(commitment, msg.sender);
    }

    /// @notice Revoke an issued credential. Allowed for an active Registrar
    ///         of the issuing university, or the governor. Revocation rules
    ///         are identical under every policy by design.
    function revoke(bytes32 commitment, bytes32 reason) external {
        Record storage rec = _records[commitment];
        if (rec.status != RecordStatus.Issued) revert NotIssued(commitment);

        Approver storage ap = _approvers[msg.sender];
        bool isRegistrar = ap.active && ap.role == Role.Registrar && ap.universityId == rec.universityId;
        if (!isRegistrar && !hasRole(GOVERNOR_ROLE, msg.sender)) revert NotAuthorizedToRevoke(msg.sender);

        rec.status = RecordStatus.Revoked;
        rec.revokedAt = uint64(block.timestamp);
        rec.revocationReason = reason;
        emit CredentialRevoked(commitment, rec.universityId, msg.sender, reason);
    }

    // ---------------------------------------------------------------------
    // Verification (free to call; no transaction needed)
    // ---------------------------------------------------------------------

    /// @notice Commitment = keccak256(abi.encode(DOMAIN, documentHash, salt)).
    function computeCommitment(bytes32 documentHash, bytes32 salt) public pure returns (bytes32) {
        return keccak256(abi.encode(COMMITMENT_DOMAIN, documentHash, salt));
    }

    function verify(bytes32 commitment) public view returns (VerificationResult memory result) {
        Record storage rec = _records[commitment];
        RecordStatus s = rec.status;
        if (s == RecordStatus.None || s == RecordStatus.Cancelled) return result; // NotFound, zeroed

        result.universityId = rec.universityId;
        result.issuerActive = _universities[rec.universityId].active;
        result.issuedAt = rec.issuedAt;
        result.revokedAt = rec.revokedAt;
        result.revocationReason = rec.revocationReason;
        if (s == RecordStatus.Pending) result.status = VerificationStatus.Pending;
        else if (s == RecordStatus.Issued) result.status = VerificationStatus.Valid;
        else result.status = VerificationStatus.Revoked;
    }

    /// @notice Convenience: verify from the document hash and salt the
    ///         holder disclosed. Any change to the document changes the hash
    ///         and therefore yields `NotFound`.
    function verifyDocument(bytes32 documentHash, bytes32 salt) external view returns (VerificationResult memory) {
        return verify(computeCommitment(documentHash, salt));
    }

    // ---------------------------------------------------------------------
    // Read helpers (used by tests, scripts and experiments)
    // ---------------------------------------------------------------------

    function getUniversity(uint32 universityId) external view returns (University memory) {
        return _universities[universityId];
    }

    function getApprover(address account) external view returns (Approver memory) {
        return _approvers[account];
    }

    function activeRoleCount(uint32 universityId, Role role) external view returns (uint256) {
        return _activeRoleCount[universityId][uint8(role)];
    }

    function getRecord(bytes32 commitment) external view returns (Record memory) {
        return _records[commitment];
    }

    function getApprovers(bytes32 commitment) external view returns (address[] memory) {
        return _approvalList[commitment];
    }

    /// @notice Whether `account`'s approval of `commitment` currently counts.
    function isApprovalValid(bytes32 commitment, address account) public view returns (bool) {
        Approver storage ap = _approvers[account];
        uint64 given = _approvalNonce[commitment][account];
        return given != 0 && ap.active && given == ap.nonce && policy.isEligible(ap.role);
    }

    /// @notice Current tally and whether `finalize` would pass the policy check.
    function tally(bytes32 commitment)
        external
        view
        returns (uint256[4] memory roleCounts, uint256 totalValid, uint256 eligibleActive, bool satisfied)
    {
        Record storage rec = _records[commitment];
        if (rec.status != RecordStatus.Pending) return (roleCounts, 0, 0, false);
        (roleCounts, totalValid, eligibleActive) = _tally(commitment, rec.universityId);
        satisfied = policy.isSatisfied(roleCounts, totalValid, eligibleActive);
    }

    // ---------------------------------------------------------------------
    // Internal
    // ---------------------------------------------------------------------

    function _recordApproval(bytes32 commitment, address account, Approver memory ap) private {
        if (_approvalNonce[commitment][account] == 0) _approvalList[commitment].push(account);
        _approvalNonce[commitment][account] = ap.nonce;
        emit CredentialApproved(commitment, account, ap.role);
    }

    /// @dev Counts only approvals whose approver is still active, still in the
    ///      same university, and whose nonce has not changed since approving.
    function _tally(bytes32 commitment, uint32 universityId)
        private
        view
        returns (uint256[4] memory counts, uint256 total, uint256 eligibleActive)
    {
        bool[4] memory eligible;
        for (uint256 r = 1; r < ROLE_SLOTS; ++r) {
            eligible[r] = policy.isEligible(Role(r));
            if (eligible[r]) eligibleActive += _activeRoleCount[universityId][r];
        }

        address[] storage list = _approvalList[commitment];
        uint256 n = list.length;
        for (uint256 i; i < n; ++i) {
            address a = list[i];
            Approver storage ap = _approvers[a];
            if (ap.active && ap.universityId == universityId && _approvalNonce[commitment][a] == ap.nonce) {
                uint256 r = uint8(ap.role);
                if (eligible[r]) {
                    counts[r] += 1;
                    total += 1;
                }
            }
        }
    }

    function _requireUniversity(uint32 universityId) private view returns (University storage u) {
        u = _universities[universityId];
        if (!u.exists) revert UnknownUniversity(universityId);
    }

    function _requireApprover(address account) private view returns (Approver storage ap) {
        ap = _approvers[account];
        if (ap.nonce == 0) revert ApproverNotRegistered(account);
    }

    function _requireEligible(address account) private view returns (Approver memory ap) {
        ap = _approvers[account];
        if (ap.nonce == 0 || !ap.active) revert NotActiveApprover(account);
        if (!_universities[ap.universityId].active) revert UniversityInactive(ap.universityId);
        if (!policy.isEligible(ap.role)) revert NotEligible(account, ap.role);
    }

    function _requirePending(bytes32 commitment) private view returns (Record storage rec) {
        rec = _records[commitment];
        if (rec.status != RecordStatus.Pending) revert NotPending(commitment);
    }
}
