// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

struct Member {
    bool active;
    address upline;
    address[] directs;
    uint256 referralCode;
}

interface IMemberController {
    function register(address addr, uint256 referralCode) external;

    function getUplines(address addr, uint256 levels)
        external
        view
        returns (address[] memory);

    function getDirects(address addr) external view returns (address[] memory);

    function setCaller(address addr) external;

    function genReferralCode(address addr) external returns (uint256);

    function getMembers(address sender) external view returns (Member memory);

    function checkBurnedLP() external pure returns (bool);

    function checkMonthlyPassOrder(address sender) external view returns (bool);
}
