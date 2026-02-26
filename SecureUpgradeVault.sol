//SPDX-License-1dentifier: LGPL-3.0-on1Y
//SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

error InsufficientBalance();
error ZeroDeposit();
error TransferFailed();
error NotAuthorized();
error NotPermitidBalance();

contract SecureVault {
    uint256 maxBalance;
    address admin;
    mapping(address => uint256) private balance;

    constructor(uint256 maxBalance_, address admin_) {
        maxBalance = maxBalance_;
        admin = admin_;
    }

    // modifier

    modifier checkAmount() {
        if (msg.value < 0) revert ZeroDeposit();
        if (msg.value > maxBalance) revert NotPermitidBalance();
        _;
    }

    modifier checkBalance(uint256 amount) {
        if (balance[msg.sender] < amount) revert InsufficientBalance(); // -> Check

        _;
    }
    // event

    event DepositEvent(address indexed user, uint256 amount); // imporante siempre utilizar el indexed para que el evento tome menos gas
    event WithdrawEvent(address indexed user, uint256 amount);
    // funtions

    // extennal o public
    function Deposit() public payable checkAmount {
        balance[msg.sender] += msg.value; // msg.value es el numero del ether que manda en la transferencia
        emit DepositEvent(msg.sender, balance[msg.sender]);
    }

    function Withdraw(uint256 amount_) public checkBalance(amount_) {
        // patron Checks-Effects-Interactions.
        balance[msg.sender] -= amount_; // -> Effects
        emit WithdrawEvent(msg.sender, balance[msg.sender]);

        (bool success, ) = msg.sender.call{value: amount_}(""); // -> Interactions

        if (success = false) revert TransferFailed();
    }
    // internal
}
