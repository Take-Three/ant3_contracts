// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/ITokenRate.sol";

struct Rate {
    uint256 rate;
    uint256 lastUpdate;
}

contract TokenRate is ITokenRate, Initializable, OwnableUpgradeable {
    mapping(address => mapping(address => Rate)) public tokenRate;
    mapping(address => bool) public validCaller;

    modifier onlyValidCaller(address addr) {
        require(validCaller[addr], "Invalid caller.");
        _;
    }

    function initialize() public initializer {
        __Ownable_init();
    }

    function setCaller(address addr) public onlyOwner {
        require(!validCaller[addr], "Address already is a valid caller.");
        validCaller[addr] = true;
    }

    function updateRate(
        address fromToken,
        address toToken,
        uint256 rate
    ) public onlyValidCaller(msg.sender) {
        require(rate > 0, "Invalid rate.");

        tokenRate[fromToken][toToken].rate = rate;
        tokenRate[fromToken][toToken].lastUpdate = block.timestamp;
    }

    function getRate(address fromToken, address toToken)
        public
        view
        returns (uint256)
    {
        require(
            tokenRate[fromToken][toToken].rate > 0,
            "Token rate not found."
        );
        return tokenRate[fromToken][toToken].rate;
    }
}
