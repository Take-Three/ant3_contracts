// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../members/IMemberController.sol";
import "./interfaces/IMonthlyPassController.sol";
import "./interfaces/IFarmingPoolContract.sol";
import "./interfaces/ITokenRate.sol";

contract MonthlyPassController is
    ContextUpgradeable,
    OwnableUpgradeable,
    IMonthlyPassController
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    IFarmingPoolContract public farmingPoolContract;
    ITokenRate public tokenRateContract;
    IERC20Upgradeable public lpToken;
    IMemberController public memberController;
    address public ant3Token;
    uint256 public lastRound;
    uint256 public lastMoId;
    uint256 public lastActiveMoId;
    uint256 public today; //+ when daily check quota;
    uint256 public monthlyBlock; //block of contract deployment, will only + when 30days pass
    uint256 public dailyQuota;
    uint256 public defaultQuota;
    uint256 public reservedReward;
    mapping(uint256 => Order) public allOrders;
    mapping(uint256 => Order) public allActiveOrders;
    mapping(address => User) allUsers;

    event BuyMonthlyPass(
        uint256 moID,
        address ownerAddress,
        uint256 startTime,
        uint256 month,
        uint256 rewardAmt,
        uint256 lpUsed
    );

    event AddUplineReward(
        uint256 moID,
        uint256 fromMoID,
        address fromAddress,
        address ownerAddress,
        uint256 startTime,
        uint256 level,
        uint256 rewardAmt
    );

    function initialize(
        address _ant3Token,
        address _memberController,
        address _lpToken,
        address _farmingPoolContract,
        address _tokenRateContract
    ) public initializer {
        __Ownable_init();
        ant3Token = _ant3Token;
        memberController = IMemberController(_memberController);
        lpToken = IERC20Upgradeable(_lpToken);
        farmingPoolContract = IFarmingPoolContract(_farmingPoolContract);
        tokenRateContract = ITokenRate(_tokenRateContract);
        today = block.timestamp;
        monthlyBlock = block.timestamp;
        lastRound = 1;
        defaultQuota = 10;
        dailyQuota = defaultQuota;
    }

    function setTokenRateContract(address _tokenRateContract)
        external
        onlyOwner
    {
        tokenRateContract = ITokenRate(_tokenRateContract);
    }

    function setFarmingPoolContract(address _farmingPoolContract)
        external
        onlyOwner
    {
        farmingPoolContract = IFarmingPoolContract(_farmingPoolContract);
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

    function _setLastRound() internal {
        //daily called by frontend to set lastround
        while (block.timestamp >= monthlyBlock + 30 days) {
            lastRound++;
            monthlyBlock = monthlyBlock + 30 days;
        }
    }

    function _calculateRequiredAmount()
        private
        view
        returns (
            uint256 lpAmount,
            uint256 ant3Amount,
            uint256 uplineAmount
        )
    {
        //calculate LP Price in 100USD & ant3 reward price 200USD & upline ant3 reward 60USD
        uint256 dailyLpPrice = tokenRateContract.getRate(
            address(lpToken),
            0x76485d357f4f3FD3a48093456DBcc684c211d7b1
        );
        uint256 dailyAnt3Price = tokenRateContract.getRate(
            address(ant3Token),
            0x76485d357f4f3FD3a48093456DBcc684c211d7b1
        );
        lpAmount = (100 ether / dailyLpPrice) * 1 ether;
        ant3Amount = (200 ether / dailyAnt3Price) * 1 gwei;
        uplineAmount = (60 ether / dailyAnt3Price) * 1 gwei;
        return (lpAmount, ant3Amount, uplineAmount);
    }

    function buyMonthlyPass(uint256 month) public {
        //0 for this month, 1 for next
        require(
            month == 0 || month == 1,
            "Can only purchase this or next month's pass"
        );
        (
            uint256 lpAmount,
            uint256 ant3Amount,
            uint256 uplineAmount
        ) = _calculateRequiredAmount();
        require(
            IERC20Upgradeable(ant3Token).balanceOf(
                address(farmingPoolContract)
            ) -
                reservedReward >=
                (ant3Amount + uplineAmount),
            "Insufficient reserves in pool"
        );
        //check if user already bought
        _setLastRound();
        require(
            allUsers[msg.sender].userOrders[lastRound + month] == false,
            "User already bought this month"
        );
        _checkQuota();
        lpToken.safeTransferFrom(msg.sender, address(this), lpAmount); //*send to team address
        _addOrders(msg.sender, ant3Amount, month, lpAmount);
        _addUplineOrders(msg.sender, uplineAmount, month);
    }

    function _addOrders(
        address from,
        uint256 rewardAmt,
        uint256 month,
        uint256 lpPriceInUSD
    ) private {
        lastMoId++;
        if (month == 0) {
            allOrders[lastMoId].startTime = block.timestamp;
        } else {
            allOrders[lastMoId].startTime = monthlyBlock + 30 days;
        }
        allOrders[lastMoId].rewardAmt = rewardAmt;
        allOrders[lastMoId].lastClaimRound = 0;
        allOrders[lastMoId].owner = from;
        allOrders[lastMoId].levels = 0;

        allUsers[from].userOrders[lastRound + month] = true;

        reservedReward += rewardAmt;

        emit BuyMonthlyPass(
            lastMoId,
            from,
            allOrders[lastMoId].startTime,
            lastRound + month,
            rewardAmt,
            lpPriceInUSD
        );
    }

    function _addUplineOrders(
        address from,
        uint256 rewardAmt,
        uint256 month
    ) private {
        address[] memory uplines = memberController.getUplines(from, 6);
        for (uint256 i = 0; i < uplines.length; i++) {
            if (uplines[i] != address(0)) {
                if (allUsers[uplines[i]].userOrders[lastRound + month]) {
                    // if upline is eligible
                    lastActiveMoId++;
                    if (month == 0) {
                        allActiveOrders[lastActiveMoId].startTime = block
                            .timestamp;
                    } else {
                        allActiveOrders[lastActiveMoId].startTime =
                            monthlyBlock +
                            30 days;
                    }
                    allActiveOrders[lastActiveMoId].rewardAmt = rewardAmt / 6;
                    allActiveOrders[lastActiveMoId].lastClaimRound = 0;
                    allActiveOrders[lastActiveMoId].owner = uplines[i];
                    allActiveOrders[lastActiveMoId].levels = i + 1;
                    reservedReward += rewardAmt / 6;
                    emit AddUplineReward(
                        lastActiveMoId,
                        lastMoId,
                        from,
                        uplines[i],
                        allActiveOrders[lastActiveMoId].startTime,
                        allActiveOrders[lastActiveMoId].levels,
                        rewardAmt / 6
                    );
                }
            }
        }
    }

    function claimReward(uint256 rewardType, uint256 orderId) public {
        require(rewardType == 1 || rewardType == 2, "Invalid rewardType");

        Order storage thisOrder = allOrders[orderId];

        if (rewardType == 2) {
            thisOrder = allActiveOrders[orderId];
        }

        // check order owner
        require(thisOrder.owner == msg.sender, "Invalid Order.");

        // check order's isit fully claim
        require(thisOrder.lastClaimRound < 3, "Order has been fully claimed.");

        // calculate total unclaim reward
        uint256 totalUnclaimedRds = (3 - thisOrder.lastClaimRound);
        uint256 currentClaimRd;
        uint256 totalClaim;

        currentClaimRd = thisOrder.lastClaimRound;

        for (uint256 i = 1; i <= totalUnclaimedRds; i++) {
            currentClaimRd++;
            if (
                block.timestamp >=
                thisOrder.startTime + (currentClaimRd * 30 days) //30days in live **
            ) {
                totalClaim += thisOrder.rewardAmt / 3;

                // update last claim round
                thisOrder.lastClaimRound = currentClaimRd;
            } else {
                break;
            }
        }

        require(totalClaim > 0, "Next reward still unable to be claimed.");
        reservedReward -= totalClaim;
        farmingPoolContract.claimAnt3(thisOrder.owner, totalClaim);
    }

    function setDailyQuota(uint256 quota) public onlyOwner {
        dailyQuota = quota;
    }

    function setDefaultQuota(uint256 quota) public onlyOwner {
        defaultQuota = quota;
    }

    function _checkQuota() private {
        // reset quota everyday
        while (block.timestamp >= today + 24 hours) {
            dailyQuota = defaultQuota;
            // update today
            if (today == 0) {
                today = block.timestamp;
            } else {
                today = today + 24 hours;
            }
        }
        // check quota
        require(dailyQuota > 0, "Reached limit of quota.");
        // deduct quota
        dailyQuota--;
    }

    function getOrders(uint256 orderId) public view returns (Order memory) {
        Order storage thisOrder = allOrders[orderId];
        return thisOrder;
    }

    function getActiveOrders(uint256 orderId)
        public
        view
        returns (Order memory)
    {
        Order storage thisOrder = allActiveOrders[orderId];
        return thisOrder;
    }

    function getUsersMonthlyOrder(address user) public view returns (bool) {
        //used to get this month's order true/false *in membercontroller
        User storage thisUser = allUsers[user];
        return thisUser.userOrders[lastRound];
    }

    function checkUserMonthlyPass(address user, uint256 month)
        public
        view
        returns (bool)
    {
        User storage thisUser = allUsers[user];
        return thisUser.userOrders[month];
    }
}
