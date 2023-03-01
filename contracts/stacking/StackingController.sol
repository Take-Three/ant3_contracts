// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../token/interfaces/IAnt3.sol";
import "../members/IMemberController.sol";
import "./interfaces/IStackingPassive.sol";
import "./interfaces/IStackingActive.sol";
import "./interfaces/IStackingController.sol";

contract StackingController is
    ContextUpgradeable,
    OwnableUpgradeable,
    IERC20Receiver,
    IStackingController
{
    struct PackagePrice {
        uint256 alphaLockPeriod;
        uint256 alphaShareRate;
        uint256 betaLockPeriod;
        uint256 betaShareRate;
        uint256 gammaLockPeriod;
        uint256 gammaShareRate;
        uint256 packageId;
    }
    using SafeERC20Upgradeable for IERC20Upgradeable;
    //token addresses
    IAnt3 public ant3Token;
    IERC20Upgradeable public lpToken;
    IStackingPassive public stackingPassive;
    IStackingActive public stackingActiveL1;
    IStackingActive public stackingActiveL2;
    IStackingActive public stackingActiveL3;
    IStackingActive public stackingActiveL4;
    IStackingActive public stackingActiveL5;
    IStackingActive public stackingActiveL6;
    IMemberController public memberController;
    PackagePrice public packagePrices;

    IStackingActive[] public stackingActiveArray;
    mapping(address => uint256) public alphaAccmQty;
    mapping(address => uint256) public betaAccmQty;
    mapping(address => uint256) public gammaAccmQty;
    mapping(address => uint256) public referralRank;

    //quotas
    uint256 public today;
    uint256 public minStackForReferral; // initial with 1  10*18
    uint256 public defaultSystemQuota;
    uint256 public systemQuota; // initial will defaultSystemQuota
    uint256 public defaultUserQuota;
    mapping(address => uint256) public userQuota;
    mapping(address => uint256) public userToday;
    uint256 public maxClaimRound; // initial to 10 rounds
    uint256 public minStackAmt;
    uint256 public shareMultiplier; //used only during calculation of shares 10**12 to remedy against small rewards/high shares resulting in <0 values (in staking only)

    event NewActiveOrder(
        uint256 fromOrderID,
        uint256 activeOrderID,
        address fromAddress,
        address toAddress,
        uint256 level,
        uint256 daysActive,
        uint256 shareAmt,
        uint256 lastRound
    );
    event ControllerReceivedTokens(address from, address to, uint256 amount);
    event MissingActiveOrder(
        uint256 fromOrderID,
        address fromAddress,
        address toAddress,
        uint256 level,
        uint256 daysActive,
        uint256 shareAmt,
        uint256 lastRound
    );

    modifier onlyAnt3() {
        require(
            msg.sender == address(ant3Token),
            "Only callable from ant3Contract"
        );
        _;
    }

    function initialize(address _ant3Token, address _memberController)
        public
        initializer
    {
        __Ownable_init();
        ant3Token = IAnt3(_ant3Token);
        memberController = IMemberController(_memberController);

        packagePrices.alphaLockPeriod = 120;
        packagePrices.betaLockPeriod = 180;
        packagePrices.gammaLockPeriod = 240;

        packagePrices.alphaShareRate = 1;
        packagePrices.betaShareRate = 2;
        packagePrices.gammaShareRate = 3;

        defaultSystemQuota = 0 ether;
        systemQuota = defaultSystemQuota;
        defaultUserQuota = 0 ether;

        maxClaimRound = 10;

        minStackForReferral = 30000000000000000 wei;
        minStackAmt = 10000000000000 wei;
    }

    function setLPTokenContract(address _lpToken) external onlyOwner {
        lpToken = IERC20Upgradeable(_lpToken);
    }

    function setMemberControllerContract(address _memberController)
        external
        onlyOwner
    {
        memberController = IMemberController(_memberController);
    }

    function setStackingPassiveContract(address _stackingPassive)
        external
        onlyOwner
    {
        stackingPassive = IStackingPassive(_stackingPassive);
    }

    function setStackingActiveContract(
        address _stackingActiveL1,
        address _stackingActiveL2,
        address _stackingActiveL3,
        address _stackingActiveL4,
        address _stackingActiveL5,
        address _stackingActiveL6
    ) external onlyOwner {
        stackingActiveL1 = IStackingActive(_stackingActiveL1);
        stackingActiveArray.push(stackingActiveL1);
        stackingActiveL2 = IStackingActive(_stackingActiveL2);
        stackingActiveArray.push(stackingActiveL2);
        stackingActiveL3 = IStackingActive(_stackingActiveL3);
        stackingActiveArray.push(stackingActiveL3);
        stackingActiveL4 = IStackingActive(_stackingActiveL4);
        stackingActiveArray.push(stackingActiveL4);
        stackingActiveL5 = IStackingActive(_stackingActiveL5);
        stackingActiveArray.push(stackingActiveL5);
        stackingActiveL6 = IStackingActive(_stackingActiveL6);
        stackingActiveArray.push(stackingActiveL6);
    }

    function setMaxClaimRound(uint256 round) public onlyOwner {
        maxClaimRound = round;
    }

    function getMaxClaimRound() public view returns (uint256) {
        return maxClaimRound;
    }

    function setPackagePrice(
        uint256 packageId,
        uint256 lockPeriod,
        uint256 shareRate
    ) external onlyOwner {
        if (packageId == 1) {
            packagePrices.alphaLockPeriod = lockPeriod;
            packagePrices.alphaShareRate = shareRate;
        } else if (packageId == 2) {
            packagePrices.betaLockPeriod = lockPeriod;
            packagePrices.betaShareRate = shareRate;
        } else if (packageId == 3) {
            packagePrices.gammaLockPeriod = lockPeriod;
            packagePrices.gammaShareRate = shareRate;
        }
    }

    function getPackagePrice(uint256 packageId)
        public
        view
        returns (uint256 lockPeriod, uint256 shareRate)
    {
        if (packageId == 1) {
            return (
                packagePrices.alphaLockPeriod,
                packagePrices.alphaShareRate
            );
        } else if (packageId == 2) {
            return (packagePrices.betaLockPeriod, packagePrices.betaShareRate);
        } else if (packageId == 3) {
            return (
                packagePrices.gammaLockPeriod,
                packagePrices.gammaShareRate
            );
        }
    }

    function setMinStackForReferral(uint256 minStack) public onlyOwner {
        minStackForReferral = minStack;
    }

    function setMinStackAmt(uint256 minStack) public onlyOwner {
        minStackAmt = minStack;
    }

    function buyStackingsPackage(uint256 packageId, uint256 stackAmt) public {
        (uint256 lockPeriod, uint256 shareRate) = getPackagePrice(packageId);
        require(lockPeriod > 0 && shareRate > 0, "Invalid Package");
        require(stackAmt >= minStackAmt, "Stack amount too low");
        lpToken.safeTransferFrom(msg.sender, address(this), stackAmt);
        _setAccumulatedQty(msg.sender, packageId, stackAmt);
        _setReferralRank(msg.sender);

        uint256 fromMoId = stackingPassive.addOrders(
            msg.sender,
            stackAmt * shareRate,
            lockPeriod,
            packageId,
            stackAmt
        );

        _addStackingActiveOrders(
            msg.sender,
            stackAmt * shareRate,
            packageId,
            fromMoId
        );

        if (memberController.getMembers(msg.sender).referralCode == 0) {
            uint256 totalStack = 0;

            totalStack += alphaAccmQty[msg.sender];
            totalStack += betaAccmQty[msg.sender];
            totalStack += gammaAccmQty[msg.sender];

            if (totalStack >= minStackForReferral) {
                memberController.genReferralCode(msg.sender);
            }
        }
    }

    function _addStackingActiveOrders(
        address sender,
        uint256 userShare,
        uint256 packageId,
        uint256 fromMoId
    ) private {
        //**Referral must have at least ONE active package.
        address[] memory uplines = memberController.getUplines(sender, 6);
        for (uint256 i = 0; i < uplines.length; i++) {
            if (uplines[i] != address(0)) {
                uint256 activeDays = _calculateActiveDays(
                    packageId,
                    referralRank[uplines[i]]
                );
                if (stackingPassive.getUserClockActive(uplines[i]) == true) {
                    if (
                        i > 2 &&
                        memberController.checkMonthlyPassOrder(uplines[i]) ==
                        false
                    ) {
                        emit MissingActiveOrder(
                            fromMoId,
                            sender,
                            uplines[i],
                            i + 1,
                            activeDays,
                            userShare,
                            stackingActiveArray[i].getLastRound()
                        );
                        continue;
                    }

                    uint256 activeMoId = stackingActiveArray[i].addOrders(
                        uplines[i],
                        userShare,
                        activeDays
                    );
                    emit NewActiveOrder(
                        fromMoId,
                        activeMoId,
                        sender,
                        uplines[i],
                        i + 1,
                        activeDays,
                        userShare,
                        stackingActiveArray[i].getLastRound()
                    );
                } else {
                    emit MissingActiveOrder(
                        fromMoId,
                        sender,
                        uplines[i],
                        i + 1,
                        activeDays,
                        userShare,
                        stackingActiveArray[i].getLastRound()
                    );
                }
            }
        }
    }

    function _calculateActiveDays(uint256 packageId, uint256 rank)
        private
        pure
        returns (uint256 day)
    {
        if (packageId == 1) {
            if (rank == 1) {
                return 20;
            } else if (rank == 2) {
                return 30;
            } else if (rank == 3) {
                return 40;
            }
        } else if (packageId == 2) {
            if (rank == 1) {
                return 30;
            } else if (rank == 2) {
                return 45;
            } else if (rank == 3) {
                return 50;
            }
        } else if (packageId == 3) {
            if (rank == 1) {
                return 40;
            } else if (rank == 2) {
                return 60;
            } else if (rank == 3) {
                return 80;
            }
        }
    }

    function _setAccumulatedQty(
        address _userAddress,
        uint256 _packageId,
        uint256 _stackedAmt
    ) private {
        if (_packageId == 1) {
            alphaAccmQty[_userAddress] += _stackedAmt;
        } else if (_packageId == 2) {
            betaAccmQty[_userAddress] += _stackedAmt;
        } else if (_packageId == 3) {
            gammaAccmQty[_userAddress] += _stackedAmt;
        }
    }

    function _setReferralRank(address _userAddress) private {
        uint256 _rank = 1;

        if (
            alphaAccmQty[_userAddress] > 0.012 ether ||
            betaAccmQty[_userAddress] > 0.009 ether ||
            gammaAccmQty[_userAddress] > 0.006 ether
        ) {
            _rank = 3;
        } else if (
            alphaAccmQty[_userAddress] > 0.004 ether ||
            betaAccmQty[_userAddress] > 0.003 ether ||
            gammaAccmQty[_userAddress] > 0.002 ether
        ) {
            _rank = 2;
        }

        referralRank[_userAddress] = _rank;
    }

    function onERC20Receive(address from, uint256 amount)
        external
        onlyAnt3
        returns (bool)
    {
        emit ControllerReceivedTokens(from, address(this), amount);
        uint256 passiveAmt = (amount * 70) / 100;
        uint256 activeAmt = amount - passiveAmt;
        uint256 active1Amt = (activeAmt * 40) / 100;
        uint256 active2Amt = (activeAmt * 20) / 100;
        uint256 active3Amt = (activeAmt * 5) / 100;
        uint256 active4Amt = (activeAmt * 5) / 100;
        uint256 active5Amt = (activeAmt * 10) / 100;
        uint256 active6Amt = activeAmt -
            active1Amt -
            active2Amt -
            active3Amt -
            active4Amt -
            active5Amt;

        ant3Token.transfer(address(stackingPassive), passiveAmt);
        _afterTokenTransfer(address(stackingPassive), passiveAmt);
        ant3Token.transfer(address(stackingActiveL1), active1Amt);
        _afterTokenTransfer(address(stackingActiveL1), active1Amt);
        ant3Token.transfer(address(stackingActiveL2), active2Amt);
        _afterTokenTransfer(address(stackingActiveL2), active2Amt);
        ant3Token.transfer(address(stackingActiveL3), active3Amt);
        _afterTokenTransfer(address(stackingActiveL3), active3Amt);
        ant3Token.transfer(address(stackingActiveL4), active4Amt);
        _afterTokenTransfer(address(stackingActiveL4), active4Amt);
        ant3Token.transfer(address(stackingActiveL5), active5Amt);
        _afterTokenTransfer(address(stackingActiveL5), active5Amt);
        ant3Token.transfer(address(stackingActiveL6), active6Amt);
        _afterTokenTransfer(address(stackingActiveL6), active6Amt);
        return true;
    }

    function _afterTokenTransfer(address to, uint256 amount) internal {
        if (to.code.length > 0) {
            // token recipient is a contract, notify them
            try IERC20Receiver(to).onERC20Receive(address(this), amount) {
                // the recipient returned a bool, TODO validate if they returned true
            } catch {
                // the notification failed (maybe they don't implement the `IERC20Receiver` interface?)
            }
        }
    }

    function setDefaultQuota(uint256 _systemQuota, uint256 _userQuota)
        public
        onlyOwner
    {
        defaultSystemQuota = _systemQuota;
        defaultUserQuota = _userQuota;
    }

    function _checkQuota(address userAddress, uint256 unstackAmt) private {
        // reset quota everyday
        if (block.timestamp >= today + 24 hours) {
            systemQuota = defaultSystemQuota;

            // update today
            if (today == 0) {
                today = block.timestamp;
            } else {
                today = today + 24 hours;
            }
        }

        // reset user quota everyday
        if (block.timestamp >= userToday[userAddress] + 24 hours) {
            userQuota[userAddress] = defaultUserQuota;

            // update user today
            if (userToday[userAddress] == 0) {
                userToday[userAddress] = today;
            } else {
                userToday[userAddress] = userToday[userAddress] + 24 hours;
            }
        }

        // check user quota
        require(
            userQuota[userAddress] >= unstackAmt,
            "Reached limit of address quota."
        );

        // check system quota
        require(systemQuota >= unstackAmt, "Reached limit of system quota.");

        // deduct quota
        userQuota[userAddress] -= unstackAmt;
        systemQuota -= unstackAmt;
    }

    //claimRewards for passive & actives
    function claimRewards(uint256 contractId) public {
        if (contractId == 0) {
            stackingPassive.claimRewards(msg.sender);
        } else {
            stackingActiveArray[contractId - 1].claimRewards(msg.sender);
        }
    }

    function reclock(address userAddress) public {
        stackingPassive.reclock(userAddress);
    }

    //unstack function
    function unstackLP(uint256[] memory orderIds) public {
        require(orderIds.length <= 10, "Exceed maximum orders.");

        uint256 totalUnstack = stackingPassive.checkTotalUnstack(
            msg.sender,
            orderIds
        );

        _checkQuota(msg.sender, totalUnstack);

        uint256[] memory unstackPackage = stackingPassive.unstack(
            msg.sender,
            orderIds
        );

        // deduct accum stack
        _deductAccumulatedQty(msg.sender, unstackPackage);

        // recalculate referral rank
        _setReferralRank(msg.sender);

        // call contract transfer LP back to user address
        lpToken.transfer(msg.sender, totalUnstack);
    }

    function _deductAccumulatedQty(
        address _userAddress,
        uint256[] memory _unstackPackage
    ) private {
        if (_unstackPackage[0] > 0) {
            alphaAccmQty[_userAddress] -= _unstackPackage[0];
        }

        if (_unstackPackage[1] > 0) {
            betaAccmQty[_userAddress] -= _unstackPackage[1];
        }

        if (_unstackPackage[2] > 0) {
            gammaAccmQty[_userAddress] -= _unstackPackage[2];
        }
    }

    function version() public pure returns (string memory) {
        return "1.1";
    }

    function setShareMultiplier(uint256 mul) public onlyOwner {
        shareMultiplier = mul;
    }

    function getShareMultiplier() public view returns (uint256) {
        return shareMultiplier;
    }

    function getUserLastClaimRound(uint256 contractId, address user)
        public
        view
        returns (uint256)
    {
        if (contractId == 0) {
            return stackingPassive.getUserLastClaimRound(user);
        } else {
            return
                stackingActiveArray[contractId - 1].getUserLastClaimRound(user);
        }
    }

    function getUserCurrentClaimableRewards(address user)
        public
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (
            stackingPassive.currentClaimableRewards(user),
            stackingActiveL1.currentClaimableRewards(user),
            stackingActiveL2.currentClaimableRewards(user),
            stackingActiveL3.currentClaimableRewards(user),
            stackingActiveL4.currentClaimableRewards(user),
            stackingActiveL5.currentClaimableRewards(user),
            stackingActiveL6.currentClaimableRewards(user)
        );
    }

    function getUserTotalClaimableRewards(address user)
        public
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (
            stackingPassive.totalClaimableRewards(user),
            stackingActiveL1.totalClaimableRewards(user),
            stackingActiveL2.totalClaimableRewards(user),
            stackingActiveL3.totalClaimableRewards(user),
            stackingActiveL4.totalClaimableRewards(user),
            stackingActiveL5.totalClaimableRewards(user),
            stackingActiveL6.totalClaimableRewards(user)
        );
    }
}
