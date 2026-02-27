//SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

error InsufficientBalance();
error ZeroDeposit();
error TransferFailed();
error NotAuthorized();
error NotPermitidBalance();
error EmergencyPauseError();

contract SecureVault is ReentrancyGuard {
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
        if (msg.value > maxBalance) revert NotPermitidBalance(); // quiero controlar el balance maximo de ether que entra
        _;
    }

    modifier checkBalance(uint256 amount) {
        if (balance[msg.sender] < amount) revert InsufficientBalance(); // -> Check
        _;
    }
    // event

    event depositEvent(address indexed user, uint256 amount); // imporante siempre utilizar el indexed para que el evento tome menos gas
    event withdrawEvent(address indexed user, uint256 amount);
    event emergencyPause(address indexed triggeredBy);
    // funtions

    // extennal o public
    function deposit() public payable checkAmount {
        balance[msg.sender] += msg.value; // msg.value es el numero del ether que manda en la transferencia
        emit depositEvent(msg.sender, msg.value);
    }

    function withdraw(
        uint256 amount_
    ) public nonReentrant checkBalance(amount_) {
        // patron Checks-Effects-Interactions. y aplicame es Reentrency para que nadie pueda robar
        balance[msg.sender] -= amount_; // -> Effects
        emit withdrawEvent(msg.sender, amount_);

        (bool success, ) = msg.sender.call{value: amount_}(""); // -> Interactions

        if (success == false) revert TransferFailed();
    }

    function pause() public {
        if (msg.sender != admin) revert NotAuthorized();
        IsPaused = true;
        emit emergencyPause(msg.sender);
    }

    function unPause() public {
        if (msg.sender != admin) revert NotAuthorized();
        IsPaused = false;
    } // internal
}
