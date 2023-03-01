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
    uint256 oriClock;
    uint256 endClock;
    uint256 amount;
    address owner;
    uint256 packageId;
}

interface IStackingPassive {
    function addOrders(
        address from,
        uint256 shareAmt,
        uint256 endRound,
        uint256 packageId,
        uint256 stackAmt
    ) external returns (uint256);

    function claimRewards(address userAddress) external;

    function reclock(address userAddress) external;

    function getUserClockActive(address userAddress)
        external
        view
        returns (bool);

    function unstack(address userAddress, uint256[] memory orderIds)
        external
        returns (uint256[] memory);

    function checkTotalUnstack(address addr, uint256[] memory orderIds)
        external
        view
        returns (uint256);

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
