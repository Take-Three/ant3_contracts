// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

struct Order {
    uint256 startTime;
    uint256 rewardAmt;
    address owner;
    uint256 lastClaimRound; //total 3 claims
    uint256 levels;
}

struct User {
    mapping(uint256 => bool) userOrders;
}

interface IMonthlyPassController {
    function getUsersMonthlyOrder(address user) external view returns (bool);
}
