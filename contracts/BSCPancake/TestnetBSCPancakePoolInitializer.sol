// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./PancakePairInterface.sol";

interface IWBNBTest {
    function deposit() external payable;

    function transfer(address dst, uint256 wad) external returns (bool);
}

// contract TestSacrifice {
//     constructor(address payable _recipient) payable {
//         selfdestruct(_recipient);
//     }
// }

contract TestnetBSCPancakePoolInitializer is OwnableUpgradeable {
    address bscAnt3Address;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    function initialize() public initializer {
        __Ownable_init();
        bscAnt3Address = 0x61cBa12ea185360DB5650EB79dbcc59417aFD5C3;
    }

    receive() external payable {}

    function executeTransfer(uint256 ant3Amt, uint256 bnbAmt)
        external
        onlyOwner
    {
        address pool = 0x7fDaacDa810CDf3f91D9bA8cBeEf971eFF7b27dC;
        address wbnbAddress = 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd;
        IERC20Upgradeable(bscAnt3Address).transfer(pool, ant3Amt);
        IWBNBTest(wbnbAddress).deposit{value: bnbAmt}();
        IWBNBTest(wbnbAddress).transfer(pool, bnbAmt);
        // (new TestSacrifice){value: bnbAmt}(payable(pool));
        PancakePairInterface(pool).sync();
    }
}
