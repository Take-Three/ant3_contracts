// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

interface INodeController {
    function getMaxClaimRound() external view returns (uint256);
}
