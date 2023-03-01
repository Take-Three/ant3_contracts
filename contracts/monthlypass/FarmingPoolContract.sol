// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "./interfaces/IMonthlyPassController.sol";
import "./interfaces/IFarmingPoolContract.sol";
import "../token/interfaces/IAnt3.sol";

contract FarmingPoolContract is
    IFarmingPoolContract,
    ContextUpgradeable,
    OwnableUpgradeable
{
    IMonthlyPassController public monthlyPassControllerContract;
    IAnt3 public ant3Token;

    modifier onlyMonthlyPassController() {
        require(
            msg.sender == address(monthlyPassControllerContract),
            "Only callable from monthlyPassContract"
        );
        _;
    }

    function initialize(address _ant3Token) public initializer {
        __Ownable_init();
        ant3Token = IAnt3(_ant3Token);
    }

    function setMonthlyPassContract(address _contractAddress)
        external
        onlyOwner
    {
        monthlyPassControllerContract = IMonthlyPassController(
            _contractAddress
        );
    }

    function claimAnt3(address user, uint256 totalClaim)
        public
        onlyMonthlyPassController
    {
        ant3Token.transfer(user, totalClaim);
    }
}
