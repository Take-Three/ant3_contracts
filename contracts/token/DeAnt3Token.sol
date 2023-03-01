// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20CappedUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./interfaces/IDeAnt3.sol";

contract DeAnt3Token is ERC20CappedUpgradeable, OwnableUpgradeable, IDeAnt3 {
    string private _name;
    string private _symbol;
    uint8 private _decimals;
    uint256 private _rewardAmt; //unused
    uint256 private _cap;
    uint256 private _taxFee;
    uint256 public totalBurned;
    address[] private _signers;
    mapping(address => bool) public _mapSigners;
    mapping(uint256 => bool) public uniqueIdExists;
    mapping(address => uint256) public userTotalBurned;
    address nodeControllerContract;
    mapping(uint256 => uint256) private _rewardAmtInPackage;

    modifier onlyController() {
        require(
            msg.sender == nodeControllerContract,
            "Only callable from nodeControllerContract"
        );
        _;
    }

    function initialize(
        string memory _NAME,
        string memory _SYMBOL,
        uint8 _DECIMALS,
        uint256 cap,
        uint256 initialBalance,
        uint256 taxFee
    ) public initializer {
        __Ownable_init();
        __ERC20_init(_NAME, _SYMBOL);
        __ERC20Capped_init(cap * 10**_DECIMALS);
        _name = _NAME;
        _symbol = _SYMBOL;
        _decimals = _DECIMALS;
        _rewardAmt = 0.1 ether;
        _cap = cap;
        _taxFee = taxFee;
        _mint(address(this), initialBalance);
    }

    receive() external payable {}

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function getRewardAmt(uint256 packageId) public view returns (uint256) {
        return _rewardAmtInPackage[packageId];
    }

    function setRewardAmtInWei(uint256 packageId, uint256 _newAmt)
        external
        onlyOwner
    {
        _rewardAmtInPackage[packageId] = _newAmt;
    }

    function getTaxFee() public view returns (uint256) {
        return _taxFee;
    }

    function setTaxFee(uint256 _newTaxFee) external onlyOwner {
        _taxFee = _newTaxFee;
    }

    function getSigners() external view returns (address[] memory) {
        return _signers;
    }

    function setSigners(address[] memory signers_) external virtual onlyOwner {
        _updateMap(_signers, false, _mapSigners);
        delete _signers;
        _signers = signers_;
        _updateMap(signers_, true, _mapSigners);
    }

    function mapSigner(address signer) external view returns (bool) {
        return _mapSigners[signer];
    }

    function _updateMap(
        address[] memory arr,
        bool status,
        mapping(address => bool) storage map
    ) internal {
        for (uint64 i = 0; i < arr.length; i++) {
            map[arr[i]] = status;
        }
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        if (msg.sender == owner()) {
            super.transfer(recipient, amount);
        } else {
            uint256 burnAmt = _calculateBurnAmt(amount);
            _burnAndUpdate(msg.sender, burnAmt);
            uint256 newAmt = amount - burnAmt;
            super.transfer(recipient, newAmt);
        }
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        uint256 burnAmt = _calculateBurnAmt(amount);
        _burnAndUpdate(from, burnAmt);
        uint256 newAmt = amount - burnAmt;
        super.transferFrom(from, to, newAmt);
        return true;
    }

    function _calculateBurnAmt(uint256 amount) private view returns (uint256) {
        uint256 burnAmt = (amount * _taxFee) / 100;
        return burnAmt;
    }

    function _burnAndUpdate(address account, uint256 amount) private {
        _burn(account, amount);
        totalBurned = totalBurned + amount;
        userTotalBurned[account] = userTotalBurned[account] + amount;
    }

    function setNodeControllerContract(address _contractAddress)
        external
        onlyOwner
    {
        nodeControllerContract = _contractAddress;
    }

    function nodeControllerBurn(address account, uint256 amount)
        public
        onlyController
    {
        _burnAndUpdate(account, amount);
    }

    function permitMint(
        address payable recipient,
        uint256 uniqueId,
        uint256 amount,
        uint256 deadline,
        uint8[] memory v,
        bytes32[] memory r,
        bytes32[] memory s,
        uint256 packageId
    ) public virtual {
        require(deadline >= block.timestamp, "Expired deadline");
        require(!uniqueIdExists[uniqueId], "Unique id exists");
        require(_rewardAmtInPackage[packageId] > 0, "Invalid PackageID");
        address spender = msg.sender;
        address owner = super.owner();

        bytes32 permitTxHash = keccak256(
            abi.encodePacked(
                bytes1(0x19),
                bytes1(0),
                owner,
                spender,
                recipient,
                amount,
                uniqueId,
                deadline
            )
        );

        address lastAddr = address(0);
        uint8 verifiedSigners = 0;
        for (uint64 i = 0; i < v.length; i++) {
            address recovered = ecrecover(permitTxHash, v[i], r[i], s[i]);
            if (recovered > lastAddr && _mapSigners[recovered])
                verifiedSigners++;
            lastAddr = recovered;
        }
        require(verifiedSigners == _signers.length, "Invalid signers");
        uniqueIdExists[uniqueId] = true;

        (bool success, ) = recipient.call{
            value: _rewardAmtInPackage[packageId]
        }("");
        require(success, "Failed to send Mech");
        super._mint(recipient, amount);
    }
}
