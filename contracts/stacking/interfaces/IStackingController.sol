// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

interface IStackingController {
    function getMaxClaimRound() external view returns (uint256);

    function getShareMultiplier() external view returns (uint256);
}
