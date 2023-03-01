// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

interface INodeActive {
    function addOrders(
        address from,
        uint256 endRound,
        uint256 shareAmt
    ) external returns (uint256);

    function getLastRound() external view returns (uint256);

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
