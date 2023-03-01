// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

interface IFarmingPoolContract {
    function claimAnt3(address user, uint256 totalClaim) external;
}
