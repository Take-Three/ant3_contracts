// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "./IMemberController.sol";
import "../monthlypass/interfaces//IMonthlyPassController.sol";

contract MemberController is
    Initializable,
    OwnableUpgradeable,
    IMemberController
{
    address public root;
    mapping(address => Member) public members;
    mapping(address => bool) public validCaller;
    uint256 private lastReferralCode;
    mapping(uint256 => address) private referralCodeList;
    mapping(address => uint256) public burnedLP;
    event Register(address addr, address referralAddr);
    IMonthlyPassController public monthlyPassControllerContract;

    modifier onlyValidMember(address addr) {
        Member storage member = members[addr];
        require(member.active, "Address not found.");
        _;
    }

    modifier onlyValidCaller(address addr) {
        require(validCaller[addr], "Invalid caller.");
        _;
    }

    function initialize(address rootAddr) public virtual initializer {
        __Ownable_init();

        Member storage member = members[rootAddr];
        member.upline = address(0);
        member.active = true;
        member.referralCode = 100000;
        lastReferralCode = 100000;
        referralCodeList[100000] = rootAddr;

        root = rootAddr;
    }

    function register(address addr, uint256 referralCode) public override {
        address referralAddr = referralCodeList[referralCode];

        require(referralAddr != address(0), "Invalid referral code.");

        Member storage member = members[addr];
        Member storage upline = members[referralAddr];

        require(!member.active, "Address has been registered.");
        require(upline.active, "Referral's address not found.");

        member.upline = referralAddr;
        member.active = true;
        upline.directs.push(addr);

        emit Register(addr, referralAddr);
    }

    function getUplines(address addr, uint256 levels)
        public
        view
        override
        onlyValidMember(addr)
        returns (address[] memory)
    {
        address[] memory uplines = new address[](levels);
        address curAddr = addr;

        for (uint256 i = 0; i < levels; i++) {
            curAddr = _getUpline(curAddr);
            if (curAddr == address(0)) break;
            uplines[i] = curAddr;
        }

        return uplines;
    }

    function _getUpline(address addr) internal view returns (address) {
        Member storage member = members[addr];
        return member.upline;
    }

    function getDirects(address addr)
        public
        view
        override
        onlyValidMember(addr)
        returns (address[] memory)
    {
        Member storage member = members[addr];
        return member.directs;
    }

    function setCaller(address addr) public override onlyOwner {
        require(!validCaller[addr], "Address already is a valid caller.");
        validCaller[addr] = true;
    }

    function genReferralCode(address addr)
        public
        override
        onlyValidCaller(msg.sender)
        returns (uint256)
    {
        Member storage member = members[addr];
        require(
            member.referralCode == 0,
            "Address already have referral code."
        );
        lastReferralCode++;

        member.referralCode = lastReferralCode;
        referralCodeList[lastReferralCode] = addr;

        return lastReferralCode;
    }

    function getMembers(address sender) public view returns (Member memory) {
        Member storage thisMember = members[sender];
        return thisMember;
    }

    function checkBurnedLP() public pure returns (bool) {
        return false;
    }

    function checkMonthlyPassOrder(address sender) public view returns (bool) {
        if (monthlyPassControllerContract.getUsersMonthlyOrder(sender)) {
            return true;
        } else {
            return false;
        }
    }

    function setMonthlyPassContract(address _contractAddress)
        external
        onlyOwner
    {
        monthlyPassControllerContract = IMonthlyPassController(
            _contractAddress
        );
    }

    receive() external payable {
        revert();
    }

    fallback() external payable {
        revert();
    }
}
