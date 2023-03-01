// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

interface ITokenRate {
    function getRate(address fromToken, address toToken)
        external
        view
        returns (uint256);
}
