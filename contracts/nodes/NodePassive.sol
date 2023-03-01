// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "../token/interfaces/IAnt3.sol";
import "./interfaces/INodePassive.sol";
import "./interfaces/INodeController.sol";
import "../helpers/BinarySearchByStorage.sol";

contract NodePassive is
    ContextUpgradeable,
    OwnableUpgradeable,
    INodePassive,
    IERC20Receiver
{
    using Arrays2 for uint256[];
    IAnt3 public ant3Token;
    INodeController public nodeControllerContract;
    uint256 public dividingValue;
    uint256 public lastRound;
    uint256 public lastMoId;
    uint256[] public sortedRoundForDeductShare;
    mapping(uint256 => uint256) public roundDeductShare;
    mapping(uint256 => Round) public rounds;
    mapping(uint256 => Order) public allOrders;
    mapping(address => User) public allUsers;
    mapping(uint256 => uint256) public roundTime;
    mapping(address => bool) public userClockActive;
    mapping(address => mapping(uint256 => uint256)) userValidOrderCount;

    event NewOrder(
        uint256 packageId,
        uint256 lastMoId,
        uint256 shareAmt,
        address from,
        uint256 lastRound,
        uint256 tokenUsed
    );
    event ReceivedTokens(address from, address to, uint256 amount);
    event SolidateRound(
        uint256 lastRound,
        uint256 toDistribute,
        uint256 totalAccuShare
    );

    modifier onlyController() {
        require(
            msg.sender == address(nodeControllerContract),
            "Only callable from nodeControllerContract"
        );
        _;
    }

    function initialize(address _nodeControllerContract, address _ant3Token)
        public
        initializer
    {
        __Ownable_init();
        nodeControllerContract = INodeController(_nodeControllerContract);
        ant3Token = IAnt3(_ant3Token);
        dividingValue = 30;
    }

    function setNodeControllerContract(address _contractAddress)
        external
        onlyOwner
    {
        nodeControllerContract = INodeController(_contractAddress);
    }

    function onERC20Receive(address from, uint256 amount)
        external
        onlyController
        returns (bool)
    {
        emit ReceivedTokens(from, address(this), amount);
        _updateRounds(amount);
        return true;
    }

    function setDividingValue(uint256 _newValue) external onlyOwner {
        dividingValue = _newValue;
    }

    //called when user purchase package on NodeController
    function addOrders(
        address from,
        uint256 shareAmt,
        uint256 packageId,
        uint256 deAntPrice
    ) public onlyController returns (uint256 moId) {
        userClockActive[from] = true;
        lastMoId++;
        allOrders[lastMoId].startRound = lastRound;
        allOrders[lastMoId].endRound = 0;
        allOrders[lastMoId].shareReward = shareAmt;
        allOrders[lastMoId].owner = from;
        allOrders[lastMoId].packageId = packageId;

        allUsers[from].roundAddShare[lastRound] += shareAmt;
        allUsers[from].userOrders.push(lastMoId);

        userValidOrderCount[from][packageId]++;

        if (allUsers[from].sortedRoundForAddShare.length > 0) {
            if (
                allUsers[from].sortedRoundForAddShare[
                    allUsers[from].sortedRoundForAddShare.length - 1
                ] != lastRound
            ) {
                allUsers[from].roundAddShare[lastRound] += allUsers[from]
                    .roundAddShare[
                        allUsers[from].sortedRoundForAddShare[
                            allUsers[from].sortedRoundForAddShare.length - 1
                        ]
                    ];
                allUsers[from].sortedRoundForAddShare.push(lastRound);
            }
        } else {
            allUsers[from].lastClaimRound = lastRound - 1;
            allUsers[from].sortedRoundForAddShare.push(lastRound);
        }

        rounds[lastRound].accmStakedShare += shareAmt;
        emit NewOrder(
            packageId,
            lastMoId,
            shareAmt,
            from,
            lastRound,
            deAntPrice
        );
        return lastMoId;
    }

    //called when contract receive funds after Ant3 mints over
    function _updateRounds(uint256 totalReceivedAmount) private {
        _checkAndInitializeNewRounds();

        rounds[lastRound].toDistribute += totalReceivedAmount / dividingValue;
        rounds[lastRound].toCarryForward += (totalReceivedAmount -
            totalReceivedAmount /
            dividingValue);
    }

    function _checkAndInitializeNewRounds() private {
        //everything in here only add once while initial new rounds
        if (block.timestamp >= rounds[lastRound].startTime + 24 hours) {
            lastRound++;
            if (lastRound > 1) {
                //take last rounds startTime + 24hours
                rounds[lastRound].startTime =
                    rounds[lastRound - 1].startTime +
                    24 hours;

                rounds[lastRound].toDistribute =
                    rounds[lastRound - 1].toCarryForward /
                    dividingValue;
                rounds[lastRound].toCarryForward = (rounds[lastRound - 1]
                    .toCarryForward -
                    rounds[lastRound - 1].toCarryForward /
                    dividingValue);
                rounds[lastRound].accmStakedShare += rounds[lastRound - 1]
                    .accmStakedShare;

                uint256 globalIndex = sortedRoundForDeductShare.findUpperBound(
                    lastRound - 1,
                    0
                );
                uint256 totalAccuShare = rounds[lastRound - 1].accmStakedShare;

                if (globalIndex > 0) {
                    globalIndex--;
                    totalAccuShare -= roundDeductShare[
                        sortedRoundForDeductShare[globalIndex]
                    ];
                }

                emit SolidateRound(
                    lastRound - 1,
                    rounds[lastRound - 1].toDistribute,
                    totalAccuShare
                );
            } else {
                //to initialize first round with timestamp
                rounds[lastRound].startTime = block.timestamp;
            }
        }
    }

    function getRounds(uint256 roundId) public view returns (Round memory) {
        Round storage thisRound = rounds[roundId];
        return thisRound;
    }

    function getOrders(uint256 orderId) public view returns (Order memory) {
        Order storage thisOrder = allOrders[orderId];
        return thisOrder;
    }

    function getUserInRound(
        address user,
        uint256 round,
        uint256 endRound
    )
        public
        view
        returns (
            uint256,
            uint256[] memory,
            uint256,
            uint256[] memory,
            uint256,
            uint256[] memory
        )
    {
        User storage thisUser = allUsers[user];
        return (
            thisUser.startingIndexForAddShare,
            thisUser.sortedRoundForAddShare,
            thisUser.roundAddShare[round],
            thisUser.sortedRoundForDeductShare,
            thisUser.roundDeductShare[endRound],
            thisUser.userOrders
        );
    }

    function getUserLastClaimRound(address user)
        external
        view
        returns (uint256)
    {
        User storage thisUser = allUsers[user];
        return (thisUser.lastClaimRound);
    }

    function expireOrder(
        address userAddress,
        uint256 orderId,
        uint256 expireRound
    ) public onlyController returns (uint256 highestPackage, bool updateRank) {
        if (
            allOrders[orderId].owner == userAddress &&
            allOrders[orderId].endRound == 0
        ) {
            // get order's share and stop order
            uint256 orderShare = allOrders[orderId].shareReward;
            // stop order
            allOrders[orderId].endRound = expireRound;
            // deduct user share
            if (allUsers[userAddress].sortedRoundForDeductShare.length > 0) {
                if (
                    allUsers[userAddress].sortedRoundForDeductShare[
                        allUsers[userAddress].sortedRoundForDeductShare.length -
                            1
                    ] != expireRound
                ) {
                    allUsers[userAddress].roundDeductShare[
                        expireRound
                    ] += allUsers[userAddress].roundDeductShare[
                        allUsers[userAddress].sortedRoundForDeductShare[
                            allUsers[userAddress]
                                .sortedRoundForDeductShare
                                .length - 1
                        ]
                    ];
                    allUsers[userAddress].sortedRoundForDeductShare.push(
                        expireRound
                    );
                }
            } else {
                allUsers[userAddress].sortedRoundForDeductShare.push(
                    expireRound
                );
            }
            allUsers[userAddress].roundDeductShare[expireRound] += orderShare;
            // deduct global share
            if (sortedRoundForDeductShare.length > 0) {
                if (
                    sortedRoundForDeductShare[
                        sortedRoundForDeductShare.length - 1
                    ] != expireRound
                ) {
                    roundDeductShare[expireRound] += roundDeductShare[
                        sortedRoundForDeductShare[
                            sortedRoundForDeductShare.length - 1
                        ]
                    ];
                    sortedRoundForDeductShare.push(expireRound);
                }
            } else {
                sortedRoundForDeductShare.push(expireRound);
            }
            roundDeductShare[expireRound] += orderShare;
            //deduct userValidOrderCount
            userValidOrderCount[userAddress][allOrders[orderId].packageId]--;
            // get user highest active package
            highestPackage = 0;
            if (userValidOrderCount[userAddress][3] > 0) {
                highestPackage = 3;
            } else if (userValidOrderCount[userAddress][2] > 0) {
                highestPackage = 2;
            } else if (userValidOrderCount[userAddress][1] > 0) {
                highestPackage = 1;
            }
            if (highestPackage == 0) {
                userClockActive[userAddress] = false;
            }
            return (highestPackage, true);
        } else {
            return (highestPackage, false);
        }
    }

    function getUserClockActive(address userAddress)
        public
        view
        returns (bool)
    {
        return userClockActive[userAddress];
    }

    function claimRewards(address userAddress) public onlyController {
        require(
            lastRound - 1 > allUsers[userAddress].lastClaimRound,
            "Nothing left to claim"
        );
        uint256 totalUnclaimedRds = (lastRound - 1) -
            allUsers[userAddress].lastClaimRound;
        uint256 maxClaimRds = _getMaxClaimRound();

        if (totalUnclaimedRds > maxClaimRds) {
            totalUnclaimedRds = maxClaimRds;
        }

        uint256 userShare;
        uint256 totalShare;
        uint256 rewardPerShare;
        uint256 totalClaim;
        uint256 currentRound = allUsers[userAddress].lastClaimRound;
        uint256 globalIndex;
        for (uint256 i = 0; i < totalUnclaimedRds; i++) {
            currentRound++;

            if (currentRound >= lastRound) {
                currentRound--;
                break;
            }

            userShare = _calculateUserTotalShare(userAddress, currentRound);
            if (userShare > 0) {
                totalShare = rounds[currentRound].accmStakedShare;

                globalIndex = sortedRoundForDeductShare.findUpperBound(
                    currentRound,
                    0
                );

                if (globalIndex > 0) {
                    globalIndex--;
                    totalShare -= roundDeductShare[
                        sortedRoundForDeductShare[globalIndex]
                    ];
                }

                rewardPerShare = rounds[currentRound].toDistribute / totalShare;
                totalClaim += userShare * rewardPerShare;
            } else {
                if (
                    allUsers[userAddress].sortedRoundForAddShare.length >
                    allUsers[userAddress].startingIndexForAddShare + 1
                ) {
                    currentRound =
                        allUsers[userAddress].sortedRoundForAddShare[
                            allUsers[userAddress].startingIndexForAddShare + 1
                        ] -
                        1;
                } else {
                    break;
                }
            }
        }

        allUsers[userAddress].lastClaimRound = currentRound;
        require(totalClaim > 0, "Nothing left to claim (2)");
        ant3Token.transfer(userAddress, totalClaim);
    }

    function _calculateUserTotalShare(address userAddress, uint256 round)
        private
        returns (uint256)
    {
        uint256 totalShare;
        uint256 totalAddShare;
        uint256 totalDeductShare;

        // add share (already set user lastclaimround = user first purchase round -1)
        uint256 addShareIndex = allUsers[userAddress]
            .sortedRoundForAddShare
            .findUpperBound(
                round,
                allUsers[userAddress].startingIndexForAddShare
            ) - 1;
        totalAddShare = allUsers[userAddress].roundAddShare[
            allUsers[userAddress].sortedRoundForAddShare[addShareIndex]
        ];

        // deduct share (since cannot special handle like add share, thus more condition needed)
        uint256 deductShareIndex = allUsers[userAddress]
            .sortedRoundForDeductShare
            .findUpperBound(
                round,
                allUsers[userAddress].startingIndexForDeductShare
            );

        if (deductShareIndex > 0) {
            deductShareIndex--;
            totalDeductShare = allUsers[userAddress].roundDeductShare[
                allUsers[userAddress].sortedRoundForDeductShare[
                    deductShareIndex
                ]
            ];
        }

        totalShare = totalAddShare - totalDeductShare;
        allUsers[userAddress].startingIndexForAddShare = addShareIndex;
        allUsers[userAddress].startingIndexForDeductShare = deductShareIndex;

        return totalShare;
    }

    //get maximum claim round/
    function _getMaxClaimRound() private view returns (uint256) {
        return nodeControllerContract.getMaxClaimRound();
    }

    //get globalSorted
    function getSortedRoundDeductShare()
        public
        view
        returns (uint256[] memory)
    {
        return sortedRoundForDeductShare;
    }

    function version() public pure returns (string memory) {
        return "1.4";
    }

    function currentClaimableRewards(address userAddress)
        public
        view
        onlyController
        returns (uint256)
    {
        uint256 totalUnclaimedRds = (lastRound - 1) -
            allUsers[userAddress].lastClaimRound;
        uint256 maxClaimRds = _getMaxClaimRound();

        if (totalUnclaimedRds > maxClaimRds) {
            totalUnclaimedRds = maxClaimRds;
        }

        uint256 userShare;
        uint256 totalShare;
        uint256 rewardPerShare;
        uint256 totalClaim;
        uint256 currentRound = allUsers[userAddress].lastClaimRound;
        uint256 globalIndex;
        for (uint256 i = 0; i < totalUnclaimedRds; i++) {
            currentRound++;

            if (currentRound >= lastRound) {
                currentRound--;
                break;
            }

            userShare = _calculateUserTotalShareView(userAddress, currentRound);
            if (userShare > 0) {
                totalShare = rounds[currentRound].accmStakedShare;

                globalIndex = sortedRoundForDeductShare.findUpperBound(
                    currentRound,
                    0
                );

                if (globalIndex > 0) {
                    globalIndex--;
                    totalShare -= roundDeductShare[
                        sortedRoundForDeductShare[globalIndex]
                    ];
                }
                rewardPerShare = rounds[currentRound].toDistribute / totalShare;
                totalClaim += userShare * rewardPerShare;
            } else {
                if (
                    allUsers[userAddress].sortedRoundForAddShare.length >
                    allUsers[userAddress].startingIndexForAddShare + 1
                ) {
                    currentRound =
                        allUsers[userAddress].sortedRoundForAddShare[
                            allUsers[userAddress].startingIndexForAddShare + 1
                        ] -
                        1;
                } else {
                    break;
                }
            }
        }

        return (totalClaim);
    }

    function totalClaimableRewards(address userAddress)
        public
        view
        onlyController
        returns (uint256)
    {
        uint256 totalUnclaimedRds = (lastRound - 1) -
            allUsers[userAddress].lastClaimRound;

        uint256 userShare;
        uint256 totalShare;
        uint256 rewardPerShare;
        uint256 totalClaim;
        uint256 currentRound = allUsers[userAddress].lastClaimRound;
        uint256 globalIndex;
        for (uint256 i = 0; i < totalUnclaimedRds; i++) {
            currentRound++;
            userShare = _calculateUserTotalShareView(userAddress, currentRound);
            if (userShare > 0) {
                totalShare = rounds[currentRound].accmStakedShare;

                globalIndex = sortedRoundForDeductShare.findUpperBound(
                    currentRound,
                    0
                );

                if (globalIndex > 0) {
                    globalIndex--;
                    totalShare -= roundDeductShare[
                        sortedRoundForDeductShare[globalIndex]
                    ];
                }

                rewardPerShare = rounds[currentRound].toDistribute / totalShare;
                totalClaim += userShare * rewardPerShare;
            }
        }

        return (totalClaim);
    }

    function _calculateUserTotalShareView(address userAddress, uint256 round)
        private
        view
        returns (uint256)
    {
        uint256 totalShare;
        uint256 totalAddShare;
        uint256 totalDeductShare;

        // add share (already set user lastclaimround = user first purchase round -1)
        uint256 addShareIndex = allUsers[userAddress]
            .sortedRoundForAddShare
            .findUpperBound(
                round,
                allUsers[userAddress].startingIndexForAddShare
            );

        if (addShareIndex > 0) {
            addShareIndex--;
            totalAddShare = allUsers[userAddress].roundAddShare[
                allUsers[userAddress].sortedRoundForAddShare[addShareIndex]
            ];
        }

        // deduct share (since cannot special handle like add share, thus more condition needed)
        uint256 deductShareIndex = allUsers[userAddress]
            .sortedRoundForDeductShare
            .findUpperBound(
                round,
                allUsers[userAddress].startingIndexForDeductShare
            );

        if (deductShareIndex > 0) {
            deductShareIndex--;
            totalDeductShare = allUsers[userAddress].roundDeductShare[
                allUsers[userAddress].sortedRoundForDeductShare[
                    deductShareIndex
                ]
            ];
        }

        totalShare = totalAddShare - totalDeductShare;

        return totalShare;
    }
}
