// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

interface IERC20Receiver {
    function onERC20Receive(address from, uint256 amount)
        external
        returns (bool);
}

interface IAnt3 {
    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function mint(uint256 amount) external;
}
