//SPDX-License-1dentifier: LGPL-3.0-on1Y
//SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

error InsufficientBalance();
error ZeroDeposit();
error TransferFailed();
error NotAuthorized();
error NotPermitidBalance();
error EmergencyPauseError();

contract SecureVault {
    uint256 public maxBalance;
    address private admin;
    mapping(address => uint256) private balance;
    bool public IsPaused;

    constructor(uint256 maxBalance_, address admin_) {
        maxBalance = maxBalance_;
        admin = admin_;
        IsPaused = false;
    }

    // modifier

    modifier checkAmount() {
        if (IsPaused == true) revert EmergencyPauseError();
        if (msg.value == 0) revert ZeroDeposit();
        if (msg.value > maxBalance) revert NotPermitidBalance();
        _;
    }

    modifier checkBalance(uint256 amount) {
        if (IsPaused == true) revert EmergencyPauseError();
        if (balance[msg.sender] < amount) revert InsufficientBalance(); // -> Check
        _;
    }
    // event

    event DepositEvent(address indexed user, uint256 amount); // imporante siempre utilizar el indexed para que el evento tome menos gas
    event WithdrawEvent(address indexed user, uint256 amount);
    event EmergencyPause(address indexed triggeredBy);
    // funtions

    // extennal o public
    function deposit() public payable checkAmount {
        balance[msg.sender] += msg.value; // msg.value es el numero del ether que manda en la transferencia
        emit DepositEvent(msg.sender, msg.value);
    }

    function withdraw(uint256 amount_) public checkBalance(amount_) {
        // patron Checks-Effects-Interactions.
        balance[msg.sender] -= amount_; // -> Effects
        emit WithdrawEvent(msg.sender, balance[msg.sender]);

        (bool success, ) = msg.sender.call{value: amount_}(""); // -> Interactions

        if (success == false) revert TransferFailed();
    }

    function pause() public {
        if (msg.sender != admin) revert NotAuthorized();
        IsPaused = true;
        emit EmergencyPause(msg.sender);
    }

    function unPause() public {
        if (msg.sender != admin) revert NotAuthorized();
        IsPaused = false;
    } // internal
}
