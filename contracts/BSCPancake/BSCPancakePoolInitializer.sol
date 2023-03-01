// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./PancakePairInterface.sol";

interface IWBNB {
    function deposit() external payable;

    function transfer(address dst, uint256 wad) external returns (bool);
}

contract BSCPancakePoolInitializer is OwnableUpgradeable {
    address bscAnt3Address;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    function initialize() public initializer {
        __Ownable_init();
        bscAnt3Address = 0x3F0432658a27b5802d8B24A6436e7A621dDCb51D;
    }

    receive() external payable {}

    function executeTransfer(uint256 ant3Amt, uint256 bnbAmt)
        external
        onlyOwner
    {
        address pool = 0xfD5CB1FcAC80D30660BA519255B37Af642Cbe2DD;
        address wbnbAddress = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
        IERC20Upgradeable(bscAnt3Address).transfer(pool, ant3Amt);
        IWBNB(wbnbAddress).deposit{value: bnbAmt}();
        IWBNB(wbnbAddress).transfer(pool, bnbAmt);
        PancakePairInterface(pool).sync();
    }
}
