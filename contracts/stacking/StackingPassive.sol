// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "../token/interfaces/IAnt3.sol";
import "./interfaces/IStackingPassive.sol";
import "./interfaces/IStackingController.sol";
import "../helpers/BinarySearchByStorage.sol";

contract StackingPassive is
    ContextUpgradeable,
    OwnableUpgradeable,
    IStackingPassive,
    IERC20Receiver
{
    using Arrays2 for uint256[];
    IAnt3 public ant3Token;
    IStackingController public stackingControllerContract;
    uint256 public dividingValue;
    uint256 public lastRound;
    uint256 public lastMoId;
    uint256[] public sortedRoundForDeductShare;
    mapping(uint256 => uint256) public roundDeductShare;
    mapping(uint256 => Round) public rounds;
    mapping(uint256 => Order) public allOrders;
    mapping(address => User) public allUsers;
    mapping(uint256 => uint256) public roundTime;
    mapping(address => uint256) public userClockActive;

    event NewOrder(
        uint256 packageId,
        uint256 lastMoId,
        uint256 shareAmt,
        address from,
        uint256 lastRound,
        uint256 stackAmt
    );
    event ReceivedTokens(address from, address to, uint256 amount);
    event SolidateRound(
        uint256 lastRound,
        uint256 toDistribute,
        uint256 totalAccuShare
    );

    modifier onlyController() {
        require(
            msg.sender == address(stackingControllerContract),
            "Only callable from stackingControllerContract"
        );
        _;
    }

    function initialize(address _stackingControllerContract, address _ant3Token)
        public
        initializer
    {
        __Ownable_init();
        stackingControllerContract = IStackingController(
            _stackingControllerContract
        );
        ant3Token = IAnt3(_ant3Token);
        dividingValue = 30;
    }

    function setStackingControllerContract(address _contractAddress)
        external
        onlyOwner
    {
        stackingControllerContract = IStackingController(_contractAddress);
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

    //called when user purchase package on StackingController
    function addOrders(
        address from,
        uint256 shareAmt,
        uint256 clock,
        uint256 packageId,
        uint256 stackAmt
    ) public onlyController returns (uint256 moId) {
        _checkAndInitializeNewRounds();
        uint256 latestExpired = (clock + (lastRound - 1));
        if (latestExpired > userClockActive[from]) {
            userClockActive[from] = latestExpired;
        }
        lastMoId++;
        allOrders[lastMoId].startRound = lastRound;
        allOrders[lastMoId].shareReward = shareAmt;
        allOrders[lastMoId].owner = from;
        allOrders[lastMoId].packageId = packageId;
        allOrders[lastMoId].oriClock = clock;
        allOrders[lastMoId].endClock = latestExpired;
        allOrders[lastMoId].amount = stackAmt;

        allUsers[from].roundAddShare[lastRound] += shareAmt;
        allUsers[from].userOrders.push(lastMoId);

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
        emit NewOrder(packageId, lastMoId, shareAmt, from, lastRound, stackAmt);
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

                rewardPerShare =
                    (rounds[currentRound].toDistribute *
                        stackingControllerContract.getShareMultiplier()) /
                    totalShare;
                totalClaim +=
                    (userShare * rewardPerShare) /
                    stackingControllerContract.getShareMultiplier();
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

    function getUserClockActive(address userAddress)
        public
        view
        returns (bool)
    {
        if (
            userClockActive[userAddress] > lastRound &&
            userClockActive[userAddress] > 0
        ) {
            return true;
        } else {
            return false;
        }
    }

    //get maximum claim round/
    function _getMaxClaimRound() private view returns (uint256) {
        return stackingControllerContract.getMaxClaimRound();
    }

    //get globalSorted
    function getSortedRoundDeductShare()
        public
        view
        returns (uint256[] memory)
    {
        return sortedRoundForDeductShare;
    }

    function checkTotalUnstack(address addr, uint256[] memory orderIds)
        public
        view
        returns (uint256)
    {
        uint256 totalUnstack = 0;

        for (uint256 i = 0; i < orderIds.length; i++) {
            // check order owner
            uint256 thisOrderId = orderIds[i];
            require(allOrders[thisOrderId].owner == addr, "Invalid Order.");
            require(
                allOrders[thisOrderId].endRound == 0,
                "Order has been unstacked."
            );
            // sum up all amount
            totalUnstack += allOrders[thisOrderId].amount;
        }

        return totalUnstack;
    }

    function reclock(address userAddress) public onlyController {
        require(
            allUsers[userAddress].userOrders.length > 0,
            "User have no orders."
        );

        // check whether user have no more clock
        require(
            userClockActive[userAddress] <= lastRound,
            "User still having clock running."
        );

        // loop all user's order
        uint256 latestExpired = 0;

        for (uint256 i = 0; i < allUsers[userAddress].userOrders.length; i++) {
            uint256 orderId = allUsers[userAddress].userOrders[i];

            if (allOrders[orderId].endRound == 0) {
                allOrders[orderId].endClock =
                    allOrders[orderId].oriClock +
                    (lastRound - 1);

                if (allOrders[orderId].oriClock > latestExpired) {
                    latestExpired = allOrders[orderId].oriClock;
                }
            }
        }

        // update latest clock
        userClockActive[userAddress] = latestExpired + (lastRound - 1);
    }

    function unstack(address userAddress, uint256[] memory orderIds)
        public
        onlyController
        returns (uint256[] memory unstackPackage)
    {
        unstackPackage = new uint256[](3);

        for (uint256 i = 0; i < orderIds.length; i++) {
            uint256 thisOrderId = orderIds[i];

            // check endClock
            require(
                lastRound >= allOrders[thisOrderId].endClock,
                "Order's clock still running."
            );

            // set endRound
            allOrders[thisOrderId].endRound = lastRound;

            // get order's share
            uint256 orderShare = allOrders[thisOrderId].shareReward;

            // deduct user share
            if (allUsers[userAddress].sortedRoundForDeductShare.length > 0) {
                if (
                    allUsers[userAddress].sortedRoundForDeductShare[
                        allUsers[userAddress].sortedRoundForDeductShare.length -
                            1
                    ] != lastRound
                ) {
                    allUsers[userAddress].roundDeductShare[
                        lastRound
                    ] += allUsers[userAddress].roundDeductShare[
                        allUsers[userAddress].sortedRoundForDeductShare[
                            allUsers[userAddress]
                                .sortedRoundForDeductShare
                                .length - 1
                        ]
                    ];
                    allUsers[userAddress].sortedRoundForDeductShare.push(
                        lastRound
                    );
                }
            } else {
                allUsers[userAddress].sortedRoundForDeductShare.push(lastRound);
            }
            allUsers[userAddress].roundDeductShare[lastRound] += orderShare;

            // deduct global share
            if (sortedRoundForDeductShare.length > 0) {
                if (
                    sortedRoundForDeductShare[
                        sortedRoundForDeductShare.length - 1
                    ] != lastRound
                ) {
                    roundDeductShare[lastRound] += roundDeductShare[
                        sortedRoundForDeductShare[
                            sortedRoundForDeductShare.length - 1
                        ]
                    ];
                    sortedRoundForDeductShare.push(lastRound);
                }
            } else {
                sortedRoundForDeductShare.push(lastRound);
            }
            roundDeductShare[lastRound] += orderShare;

            // record total unstack for particular package
            unstackPackage[allOrders[thisOrderId].packageId - 1] += allOrders[
                thisOrderId
            ].amount;
        }
        return (unstackPackage);
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

                rewardPerShare =
                    (rounds[currentRound].toDistribute *
                        stackingControllerContract.getShareMultiplier()) /
                    totalShare;
                totalClaim +=
                    (userShare * rewardPerShare) /
                    stackingControllerContract.getShareMultiplier();
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

                rewardPerShare =
                    (rounds[currentRound].toDistribute *
                        stackingControllerContract.getShareMultiplier()) /
                    totalShare;
                totalClaim +=
                    (userShare * rewardPerShare) /
                    stackingControllerContract.getShareMultiplier();
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
