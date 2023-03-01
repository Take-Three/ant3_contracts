// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "../token/interfaces/IDeAnt3.sol";
import "../token/interfaces/IAnt3.sol";
import "../members/IMemberController.sol";
import "./interfaces/INodePassive.sol";
import "./interfaces/INodeActive.sol";
import "./interfaces/INodeController.sol";

contract NodeController is
    ContextUpgradeable,
    OwnableUpgradeable,
    IERC20Receiver,
    INodeController
{
    struct PackagePrice {
        uint256 alphaDeAntPrice;
        uint256 alphaGuardianPrice;
        uint256 betaDeAntPrice;
        uint256 betaGuardianPrice;
        uint256 gammaDeAntPrice;
        uint256 gammaGuardianPrice;
        uint256 packageId;
    }

    //token addresses, //guardian
    IDeAnt3 public deAnt3Token;
    IAnt3 public ant3Token;
    IERC20Upgradeable public guardianToken;
    PackagePrice public packagePrices;
    INodePassive public nodePassive;
    INodeActive public nodeActiveL1;
    INodeActive public nodeActiveL2;
    INodeActive public nodeActiveL3;
    INodeActive public nodeActiveL4;
    INodeActive public nodeActiveL5;
    INodeActive public nodeActiveL6;
    INodeActive[] public nodeActiveArray;
    IMemberController public memberController;
    mapping(address => uint256) public alphaAccmQty;
    mapping(address => uint256) public betaAccmQty;
    mapping(address => uint256) public gammaAccmQty;
    mapping(address => uint256) public referralRank;
    mapping(address => bool) public validCaller;

    //quotas
    uint256 public today;
    mapping(uint256 => uint256) defaultQuota; // initial will [1:10, 2:100, 3:300]
    mapping(uint256 => uint256) allQuota; // initial will defaultQuota
    uint256 lastPromoCode; // initial with 100000
    uint256 public maxClaimRound; // initial to 10 rounds
    mapping(uint256 => address) allPromoCode;
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
    event MissingActiveOrder(
        uint256 fromOrderID,
        address fromAddress,
        address toAddress,
        uint256 level,
        uint256 daysActive,
        uint256 shareAmt,
        uint256 lastRound
    );
    event ControllerReceivedTokens(address from, address to, uint256 amount);
    uint256 deAnt3Decimals;
    uint256 guardianDecimals;
    address private _guardianCollectAddress;

    modifier onlyAnt3() {
        require(
            msg.sender == address(ant3Token),
            "Only callable from ant3Contract"
        );
        _;
    }

    modifier onlyValidCaller(address addr) {
        require(validCaller[addr], "Invalid caller.");
        _;
    }

    function initialize(
        address payable _deAnt3Token,
        address _ant3Token,
        address _guardianToken,
        address _memberController
    ) public initializer {
        __Ownable_init();
        deAnt3Token = IDeAnt3(_deAnt3Token);
        ant3Token = IAnt3(_ant3Token);
        guardianToken = IERC20Upgradeable(_guardianToken);
        memberController = IMemberController(_memberController);
        _guardianCollectAddress = 0xF18dD3538362d890Cd13e06e6688aB7288eA764F;

        deAnt3Decimals = 10**9;
        guardianDecimals = 10**18;

        packagePrices.alphaDeAntPrice = 1000 * deAnt3Decimals;
        packagePrices.alphaGuardianPrice = 100 * guardianDecimals;

        packagePrices.betaDeAntPrice = 10000 * deAnt3Decimals;
        packagePrices.betaGuardianPrice = 1000 * guardianDecimals;

        packagePrices.gammaDeAntPrice = 100000 * deAnt3Decimals;
        packagePrices.gammaGuardianPrice = 10000 * guardianDecimals;

        lastPromoCode = 100000;
        defaultQuota[1] = 300;
        defaultQuota[2] = 100;
        defaultQuota[3] = 10;
        allQuota[1] = defaultQuota[1];
        allQuota[2] = defaultQuota[2];
        allQuota[3] = defaultQuota[3];

        validCaller[owner()] = true;

        maxClaimRound = 10;
    }

    function setMemberControllerContract(address _memberController)
        external
        onlyOwner
    {
        memberController = IMemberController(_memberController);
    }

    function setGuardianCollectAddress(address guardianCollectAddress_)
        external
        onlyOwner
    {
        _guardianCollectAddress = guardianCollectAddress_;
    }

    function setNodePassiveContract(address _nodePassive) external onlyOwner {
        nodePassive = INodePassive(_nodePassive);
    }

    function setNodeActiveContract(
        address _nodeActiveL1,
        address _nodeActiveL2,
        address _nodeActiveL3,
        address _nodeActiveL4,
        address _nodeActiveL5,
        address _nodeActiveL6
    ) external onlyOwner {
        nodeActiveL1 = INodeActive(_nodeActiveL1);
        nodeActiveArray.push(nodeActiveL1);

        nodeActiveL2 = INodeActive(_nodeActiveL2);
        nodeActiveArray.push(nodeActiveL2);

        nodeActiveL3 = INodeActive(_nodeActiveL3);
        nodeActiveArray.push(nodeActiveL3);

        nodeActiveL4 = INodeActive(_nodeActiveL4);
        nodeActiveArray.push(nodeActiveL4);

        nodeActiveL5 = INodeActive(_nodeActiveL5);
        nodeActiveArray.push(nodeActiveL5);

        nodeActiveL6 = INodeActive(_nodeActiveL6);
        nodeActiveArray.push(nodeActiveL6);
    }

    function setPackagePrice(
        uint256 packageId,
        uint256 deAnt3,
        uint256 guardian
    ) external onlyOwner {
        if (packageId == 1) {
            packagePrices.alphaDeAntPrice = deAnt3;
            packagePrices.alphaGuardianPrice = guardian;
        } else if (packageId == 2) {
            packagePrices.betaDeAntPrice = deAnt3;
            packagePrices.betaGuardianPrice = guardian;
        } else if (packageId == 3) {
            packagePrices.gammaDeAntPrice = deAnt3;
            packagePrices.gammaGuardianPrice = guardian;
        }
    }

    function setMaxClaimRound(uint256 round) public onlyOwner {
        maxClaimRound = round;
    }

    function getMaxClaimRound() public view returns (uint256) {
        return maxClaimRound;
    }

    function getPackagePrice(uint256 packageId)
        public
        view
        returns (uint256 deant, uint256 guardian)
    {
        if (packageId == 1) {
            return (
                packagePrices.alphaDeAntPrice,
                packagePrices.alphaGuardianPrice
            );
        } else if (packageId == 2) {
            return (
                packagePrices.betaDeAntPrice,
                packagePrices.betaGuardianPrice
            );
        } else if (packageId == 3) {
            return (
                packagePrices.gammaDeAntPrice,
                packagePrices.gammaGuardianPrice
            );
        }
    }

    function buyNodesPackage(uint256 packageId, uint256 promoCode) public {
        (uint256 deAntPrice, uint256 guardianPrice) = getPackagePrice(
            packageId
        );
        require(
            deAntPrice > 0 && guardianPrice > 0,
            "Price must be more than 0"
        );
        _checkQuota(packageId, promoCode, msg.sender);
        deAnt3Token.nodeControllerBurn(msg.sender, deAntPrice);
        guardianToken.transferFrom(
            msg.sender,
            _guardianCollectAddress,
            guardianPrice
        );
        _setAccumulatedQty(msg.sender, packageId);
        if (packageId > referralRank[msg.sender]) {
            _setReferralRank(msg.sender, packageId);
        }
        uint256 userShare = _calculateShares(msg.sender, packageId);
        _mintAnt3Token(deAntPrice);
        uint256 fromMoId = nodePassive.addOrders(
            msg.sender,
            userShare,
            packageId,
            deAntPrice
        );
        _addNodeActiveOrders(msg.sender, userShare, packageId, fromMoId);

        if (memberController.getMembers(msg.sender).referralCode == 0) {
            memberController.genReferralCode(msg.sender);
        }
    }

    function _addNodeActiveOrders(
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
                if (nodePassive.getUserClockActive(uplines[i]) == true) {
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
                            nodeActiveArray[i].getLastRound()
                        );
                        continue;
                    }

                    uint256 activeMoId = nodeActiveArray[i].addOrders(
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
                        nodeActiveArray[i].getLastRound()
                    );
                } else {
                    emit MissingActiveOrder(
                        fromMoId,
                        sender,
                        uplines[i],
                        i + 1,
                        activeDays,
                        userShare,
                        nodeActiveArray[i].getLastRound()
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

    function _calculateShares(address _userAddress, uint256 packageId)
        private
        view
        returns (uint256 shares)
    {
        if (packageId == 3) {
            if (gammaAccmQty[_userAddress] > 10) {
                return 1200;
            } else if (
                gammaAccmQty[_userAddress] > 5 &&
                gammaAccmQty[_userAddress] < 11
            ) {
                return 1100;
            } else {
                return 1000;
            }
        } else if (packageId == 2) {
            if (betaAccmQty[_userAddress] > 10) {
                return 120;
            } else if (
                (betaAccmQty[_userAddress] > 5 &&
                    betaAccmQty[_userAddress] < 11)
            ) {
                return 110;
            } else {
                return 100;
            }
        } else if (packageId == 1) {
            if (alphaAccmQty[_userAddress] > 10) {
                return 12;
            } else if (
                (alphaAccmQty[_userAddress] > 5 &&
                    alphaAccmQty[_userAddress] < 11)
            ) {
                return 11;
            } else {
                return 10;
            }
        }
    }

    function _setAccumulatedQty(address _userAddress, uint256 _packageId)
        private
    {
        if (_packageId == 1) {
            alphaAccmQty[_userAddress]++;
        } else if (_packageId == 2) {
            betaAccmQty[_userAddress]++;
        } else if (_packageId == 3) {
            gammaAccmQty[_userAddress]++;
        }
    }

    function _setReferralRank(address _userAddress, uint256 _rank) private {
        referralRank[_userAddress] = _rank;
    }

    function _mintAnt3Token(uint256 amount) private {
        ant3Token.mint(amount);
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

        ant3Token.transfer(address(nodePassive), passiveAmt);
        _afterTokenTransfer(address(nodePassive), passiveAmt);
        ant3Token.transfer(address(nodeActiveL1), active1Amt);
        _afterTokenTransfer(address(nodeActiveL1), active1Amt);
        ant3Token.transfer(address(nodeActiveL2), active2Amt);
        _afterTokenTransfer(address(nodeActiveL2), active2Amt);
        ant3Token.transfer(address(nodeActiveL3), active3Amt);
        _afterTokenTransfer(address(nodeActiveL3), active3Amt);
        ant3Token.transfer(address(nodeActiveL4), active4Amt);
        _afterTokenTransfer(address(nodeActiveL4), active4Amt);
        ant3Token.transfer(address(nodeActiveL5), active5Amt);
        _afterTokenTransfer(address(nodeActiveL5), active5Amt);
        ant3Token.transfer(address(nodeActiveL6), active6Amt);
        _afterTokenTransfer(address(nodeActiveL6), active6Amt);
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

    function setCaller(address addr) public onlyOwner {
        require(!validCaller[addr], "Address already is a valid caller.");
        validCaller[addr] = true;
    }

    function removeCaller(address addr) public onlyOwner {
        require(validCaller[addr], "Address is not a valid caller.");
        validCaller[addr] = false;
    }

    function expireUserOrder(
        address[] memory userAddress,
        uint256[] memory orderId,
        uint256[] memory expireRound
    ) public onlyValidCaller(msg.sender) {
        require(
            userAddress.length == orderId.length &&
                userAddress.length == expireRound.length,
            "Invalid length of elements"
        );

        uint256 highestPackage;
        bool updateRank;

        for (uint256 i = 0; i < userAddress.length; i++) {
            (highestPackage, updateRank) = nodePassive.expireOrder(
                userAddress[i],
                orderId[i],
                expireRound[i]
            );
            // recalculate user ranking
            if (updateRank) {
                _setReferralRank(userAddress[i], highestPackage);
            }
        }
    }

    function setDefaultQuota(uint256 packageId, uint256 quota)
        public
        onlyOwner
    {
        defaultQuota[packageId] = quota;
    }

    function checkQuota() public view returns (uint256[] memory) {
        uint256[] memory curQuota = new uint256[](3);

        for (uint256 i = 0; i < 3; i++) {
            curQuota[i] = allQuota[i + 1];
        }

        return curQuota;
    }

    function _checkQuota(
        uint256 packageId,
        uint256 promoCode,
        address userAddress
    ) private {
        // reset quota everyday
        if (block.timestamp >= today + 24 hours) {
            for (uint256 i = 0; i < 3; i++) {
                allQuota[i + 1] = defaultQuota[i + 1];
            }
            // update today
            if (today == 0) {
                today = block.timestamp;
            } else {
                today = today + 24 hours;
            }
        }

        // check whether got promocode
        if (promoCode > 0) {
            // check promocode valid
            require(
                allPromoCode[promoCode] == userAddress,
                "Invalid Promo Code."
            );
            allPromoCode[promoCode] = address(0);
        } else {
            // check quota
            require(allQuota[packageId] > 0, "Reached limit of quota.");
            // deduct quota
            allQuota[packageId]--;
        }
    }

    function generatePromoCode(
        address[] memory userAddress,
        uint256[] memory quantity
    ) public onlyOwner {
        require(
            userAddress.length == quantity.length,
            "Invalid length of elements"
        );

        for (uint256 i = 0; i < userAddress.length; i++) {
            for (uint256 j = 0; j < quantity[i]; j++) {
                lastPromoCode++;
                // Assign promocode to useraddress
                allPromoCode[lastPromoCode] = userAddress[i];
            }
        }
    }

    //claimRewards for passive & actives
    function claimRewards(uint256 contractId) public {
        if (contractId == 0) {
            nodePassive.claimRewards(msg.sender);
        } else {
            nodeActiveArray[contractId - 1].claimRewards(msg.sender);
        }
    }

    function getUserLastClaimRound(uint256 contractId, address user)
        public
        view
        returns (uint256)
    {
        if (contractId == 0) {
            return nodePassive.getUserLastClaimRound(user);
        } else {
            return nodeActiveArray[contractId - 1].getUserLastClaimRound(user);
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
            nodePassive.currentClaimableRewards(user),
            nodeActiveL1.currentClaimableRewards(user),
            nodeActiveL2.currentClaimableRewards(user),
            nodeActiveL3.currentClaimableRewards(user),
            nodeActiveL4.currentClaimableRewards(user),
            nodeActiveL5.currentClaimableRewards(user),
            nodeActiveL6.currentClaimableRewards(user)
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
            nodePassive.totalClaimableRewards(user),
            nodeActiveL1.totalClaimableRewards(user),
            nodeActiveL2.totalClaimableRewards(user),
            nodeActiveL3.totalClaimableRewards(user),
            nodeActiveL4.totalClaimableRewards(user),
            nodeActiveL5.totalClaimableRewards(user),
            nodeActiveL6.totalClaimableRewards(user)
        );
    }
}
