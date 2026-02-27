// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Custom Errors
// Using custom errors instead of require strings reduces gas cost on revert
// (4-byte selector vs. ABI-encoded string). All revert paths use this pattern.
// ─────────────────────────────────────────────────────────────────────────────

/// @notice Thrown when the caller's recorded balance is less than the requested withdrawal amount.
error InsufficientBalance();

/// @notice Thrown when a deposit is attempted with msg.value == 0.
error ZeroDeposit();

/// @notice Thrown when the low-level ETH transfer in `withdraw` returns false.
error TransferFailed();

/// @notice Thrown when a restricted function is called by an address other than `admin`.
error NotAuthorized();

/// @notice Thrown when a deposit would exceed the per-transaction `maxBalance` cap.
error NotPermitidBalance();

/// @notice Thrown when a deposit is attempted while the contract is paused.
error EmergencyPauseError();

// ─────────────────────────────────────────────────────────────────────────────
// Contract
// ─────────────────────────────────────────────────────────────────────────────

/// @title  SecureVault
/// @notice Multi-user ETH custody contract with deposit caps, emergency pause,
///         and reentrancy protection. Designed as a minimal, security-first
///         primitive. No fee logic, no upgradeability, no implicit ETH entry.
/// @dev    Inherits OpenZeppelin's ReentrancyGuard for mutex-based reentrancy
///         protection on `withdraw`. All state-mutating functions also follow
///         the Checks-Effects-Interactions (CEI) pattern as a second layer of
///         defense. ETH can only enter through `deposit`; there is no
///         `receive()` or `fallback()` to prevent unaccounted balance growth.
contract SecureVault is ReentrancyGuard {
    // ─────────────────────────────────────────────────────────────────────────
    // State Variables
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Maximum ETH value (in wei) accepted in a single deposit transaction.
    /// @dev    Set once at construction; immutable by design. Changing this value
    ///         requires redeployment, which is intentional — upgradeability adds
    ///         proxy complexity that is out of scope for this contract.
    uint256 public maxBalance;

    /// @notice Address with exclusive authority to pause and unpause the contract.
    /// @dev    Intentionally private. Exposing admin via a getter is a minor
    ///         information leak; callers only need to know whether their tx will
    ///         succeed, not who controls the contract.
    address private admin;

    /// @notice Per-user ETH balance tracked by this contract.
    /// @dev    Private to enforce access through the public interface only.
    ///         Note: `sum(balance[i])` should equal `address(this).balance` under
    ///         normal operation, but this invariant can drift if ETH is force-sent
    ///         via `selfdestruct`. No invariant check is performed on-chain.
    mapping(address => uint256) private balance;

    /// @notice When true, new deposits are rejected. Withdrawals remain open.
    /// @dev    The asymmetry is intentional: blocking withdrawals during an
    ///         emergency would make a compromised admin key a theft vector.
    ///         Pause only gates capital inflow.
    bool public IsPaused;

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Deploys the vault with a deposit cap and designates an admin.
    /// @param  maxBalance_ Maximum wei accepted per deposit transaction.
    /// @param  admin_      Address granted pause/unpause authority.
    constructor(uint256 maxBalance_, address admin_) {
        maxBalance = maxBalance_;
        admin = admin_;
        IsPaused = false;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Modifiers
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Validates deposit preconditions in order of cheapest-to-most-expensive check:
    ///      1. Pause state  — single SLOAD.
    ///      2. Zero value   — reads msg.value from calldata (free).
    ///      3. Cap check    — compares msg.value to a storage slot.
    ///      Reverting early on cheaper checks saves gas for callers who would fail anyway.
    modifier checkAmount() {
        if (IsPaused == true) revert EmergencyPauseError();
        if (msg.value == 0) revert ZeroDeposit();
        if (msg.value > maxBalance) revert NotPermitidBalance();
        _;
    }

    /// @dev Validates that the caller has sufficient balance before any state mutation.
    ///      This is the "Checks" step of the CEI pattern for `withdraw`.
    /// @param amount The wei amount the caller intends to withdraw.
    modifier checkBalance(uint256 amount) {
        if (balance[msg.sender] < amount) revert InsufficientBalance();
        _;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Emitted on every successful deposit.
    /// @param  user   The depositing address. Indexed for efficient log filtering.
    /// @param  amount The wei amount deposited.
    event depositEvent(address indexed user, uint256 amount);

    /// @notice Emitted on every successful withdrawal.
    /// @param  user   The withdrawing address. Indexed for efficient log filtering.
    /// @param  amount The wei amount withdrawn.
    event withdrawEvent(address indexed user, uint256 amount);

    /// @notice Emitted when the admin activates the emergency pause.
    /// @param  triggeredBy The admin address that triggered the pause. Indexed for audit trail.
    event emergencyPause(address indexed triggeredBy);

    // ─────────────────────────────────────────────────────────────────────────
    // External / Public Functions
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Deposits ETH into the vault and credits the caller's balance.
    /// @dev    Guarded by `checkAmount` which enforces: not paused, non-zero value,
    ///         and value within the per-transaction cap.
    ///         There is no `receive()` fallback — ETH must enter exclusively
    ///         through this function to keep accounting deterministic.
    function deposit() public payable checkAmount {
        // msg.value is the ETH amount (in wei) attached to this transaction.
        balance[msg.sender] += msg.value;
        emit depositEvent(msg.sender, msg.value);
    }

    /// @notice Withdraws `amount_` wei from the caller's balance.
    /// @dev    Implements the Checks-Effects-Interactions pattern:
    ///           - Check:       `checkBalance` modifier (balance >= amount_).
    ///           - Effect:      Balance decremented before the external call.
    ///           - Interaction: Low-level `.call` to transfer ETH.
    ///         `nonReentrant` from ReentrancyGuard is applied as a second layer.
    ///         If both CEI and the mutex are present, an attacker must defeat both
    ///         simultaneously — defense in depth.
    ///
    ///         ⚠ KNOWN TRADE-OFF: If the `.call` fails (e.g. recipient's `receive`
    ///         reverts), the function reverts with `TransferFailed` but the balance
    ///         decrement has already occurred in this execution context. Because the
    ///         whole transaction reverts, the storage write is rolled back — the user
    ///         does NOT lose funds. This is standard EVM revert semantics.
    /// @param  amount_ The wei amount to withdraw. Must be <= caller's balance.
    function withdraw(
        uint256 amount_
    ) public nonReentrant checkBalance(amount_) {
        balance[msg.sender] -= amount_; // Effects  — update state first
        emit withdrawEvent(msg.sender, amount_);

        (bool success, ) = msg.sender.call{value: amount_}(""); // Interactions

        if (success == false) revert TransferFailed();
    }

    /// @notice Activates the emergency pause, blocking all future deposits.
    /// @dev    Restricted to `admin`. Emits `emergencyPause` for off-chain monitors.
    ///         Withdrawals are intentionally unaffected — users must always be
    ///         able to recover their funds regardless of contract state.
    function pause() public {
        if (msg.sender != admin) revert NotAuthorized();
        IsPaused = true;
        emit emergencyPause(msg.sender);
    }

    /// @notice Deactivates the emergency pause, re-enabling deposits.
    /// @dev    Restricted to `admin`. No event is emitted on unpause by design —
    ///         the absence of a pause event is itself the signal that the system
    ///         has returned to normal operation. Consider adding an event in a
    ///         future version for completeness.
    function unPause() public {
        if (msg.sender != admin) revert NotAuthorized();
        IsPaused = false;
    }
    /// @notice Updates the maximum allowed balance.
    /// @dev    Only the admin can call this function.
    ///         Sets a new value for `maxBalance`.
    /// @param  newMaxBalance_ New maximum balance allowed.
    function modifierMaxBalance(uint256 newMaxBalance_) public {
        if (msg.sender != admin) revert NotAuthorized();
        maxBalance = newMaxBalance_;
    }
}
