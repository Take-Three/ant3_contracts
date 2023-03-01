// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

struct Round {
    uint256 toDistribute;
    uint256 toCarryForward;
    uint256 accmStakedShare;
    uint256 startTime;
}

struct User {
    uint256 startingIndexForAddShare;
    uint256[] sortedRoundForAddShare;
    mapping(uint256 => uint256) roundAddShare;
    uint256 startingIndexForDeductShare;
    uint256[] sortedRoundForDeductShare;
    mapping(uint256 => uint256) roundDeductShare;
    uint256[] userOrders;
    uint256 lastClaimRound;
}

struct Order {
    uint256 startRound;
    uint256 endRound;
    uint256 shareReward;
    address owner;
    uint256 packageId;
}

interface INodePassive {
    function addOrders(
        address from,
        uint256 shareAmt,
        uint256 packageId,
        uint256 deAntPrice
    ) external returns (uint256);

    function expireOrder(
        address userAddress,
        uint256 orderId,
        uint256 expireRound
    ) external returns (uint256, bool);

    function getUserClockActive(address userAddress)
        external
        view
        returns (bool);

    function claimRewards(address userAddress) external;

    function getUserLastClaimRound(address user)
        external
        view
        returns (uint256);

    function currentClaimableRewards(address userAddress)
        external
        view
        returns (uint256);

    function totalClaimableRewards(address userAddress)
        external
        view
        returns (uint256);
}
