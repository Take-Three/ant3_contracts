// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/Math/SafeMathUpgradeable.sol";
import "./interfaces/IAnt3.sol";

contract Ant3Token is
    ContextUpgradeable,
    IERC20Upgradeable,
    OwnableUpgradeable,
    IAnt3
{
    using SafeMathUpgradeable for uint256;

    mapping(address => uint256) private _rOwned;
    mapping(address => uint256) private _tOwned;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) private _isExcludedFromFee;
    mapping(address => bool) private _isExcluded;
    address[] private _excluded;
    uint256 private constant MAX = ~uint256(0);
    uint256 private _tTotal;
    uint256 private _rTotal;
    uint256 private _tFeeTotal;
    string private _name;
    string private _symbol;
    uint256 private _decimals;
    uint256 private _taxFee;
    uint256 private _previousTaxFee;
    uint256 public totalBurned;
    uint256 public holderTaxFeePercentage;
    uint256 public teamTaxFeePercentage;
    uint256 public burnTaxFeePercentage;
    address private _teamAddress;

    address[] private _signers;
    address nodeControllerContract;
    address stackingControllerContract;

    mapping(address => bool) private _mapSigners;
    mapping(uint256 => bool) public uniqueIdExists;
    mapping(address => uint256) public userTotalBurned;
    event TransferToBurn(uint256 indexed amt);
    event TransferToTeam(uint256 indexed amt);

    address private _team2Address;
    address private _gameChangerAddress;
    address private _farmingPoolAddress;

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
        uint256 _DECIMALS,
        uint256 _supply,
        uint256 _txFee
    ) public initializer {
        __Ownable_init();

        _name = _NAME;
        _symbol = _SYMBOL;
        _decimals = _DECIMALS;
        _tTotal = _supply * 10**_decimals;
        _rTotal = (MAX - (MAX % _tTotal));
        _taxFee = _txFee;
        _previousTaxFee = _txFee;
        _rOwned[address(this)] = _rTotal;

        holderTaxFeePercentage = 10;
        teamTaxFeePercentage = 10;
        burnTaxFeePercentage = 80;

        _teamAddress = 0x3ea2d29A2B41722979EdE1F01C5B9058005088AE;
        _team2Address = 0xC3B85d0460e55b4257628962ADfaDDDb960c840A;
        _gameChangerAddress = 0xf4C5dFB03F8866ECa830d9539fbE4DBaCbC6DFfb;
        _farmingPoolAddress = 0x0d65cedb0b101948964990Fb7f689DA8Da042C3d;

        //exclude team and this contract from fee
        _isExcludedFromFee[address(this)] = true;
        excludeFromReward(address(this));
        _isExcludedFromFee[_teamAddress] = true;
        excludeFromReward(_teamAddress);

        emit Transfer(address(0), address(this), _tTotal);
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint256) {
        return _decimals;
    }

    function version() public pure virtual returns (string memory) {
        return "1";
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function getTaxFee() public view returns (uint256) {
        return _taxFee;
    }

    function setTaxFee(uint256 _newTaxFee) external onlyOwner {
        _taxFee = _newTaxFee;
    }

    function setHolderTaxFee(uint256 _newTaxFee) external onlyOwner {
        holderTaxFeePercentage = _newTaxFee;
    }

    function setBurnTaxFee(uint256 _newTaxFee) external onlyOwner {
        burnTaxFeePercentage = _newTaxFee;
    }

    function setTeamTaxFee(uint256 _newTaxFee) external onlyOwner {
        teamTaxFeePercentage = _newTaxFee;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    function transfer(address recipient, uint256 amount)
        public
        override(IAnt3, IERC20Upgradeable)
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(
                amount,
                "ERC20: transfer amount exceeds allowance"
            )
        );
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].add(addedValue)
        );
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].sub(
                subtractedValue,
                "ERC20: decreased allowance below zero"
            )
        );
        return true;
    }

    function isExcludedFromReward(address account) public view returns (bool) {
        return _isExcluded[account];
    }

    function totalFees() public view returns (uint256) {
        return _tFeeTotal;
    }

    function deliver(uint256 tAmount) public {
        address sender = _msgSender();
        require(
            !_isExcluded[sender],
            "Excluded addresses cannot call this function"
        );
        (uint256 rAmount, , , , ) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rTotal = _rTotal.sub(rAmount);
        _tFeeTotal = _tFeeTotal.add(tAmount);
    }

    function reflectionFromToken(uint256 tAmount, bool deductTransferFee)
        public
        view
        returns (uint256)
    {
        require(tAmount <= _tTotal, "Amount must be less than supply");
        if (!deductTransferFee) {
            (uint256 rAmount, , , , ) = _getValues(tAmount);
            return rAmount;
        } else {
            (, uint256 rTransferAmount, , , ) = _getValues(tAmount);
            return rTransferAmount;
        }
    }

    function tokenFromReflection(uint256 rAmount)
        public
        view
        returns (uint256)
    {
        require(
            rAmount <= _rTotal,
            "Amount must be less than total reflections"
        );
        uint256 currentRate = _getRate();
        return rAmount.div(currentRate);
    }

    function excludeFromReward(address account) public onlyOwner {
        require(!_isExcluded[account], "Account is already excluded");
        if (_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcluded[account] = true;
        _excluded.push(account);
    }

    function includeInReward(address account) external onlyOwner {
        require(_isExcluded[account], "Account is already excluded");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _tOwned[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
    }

    function excludeFromFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = true;
    }

    function includeInFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = false;
    }

    function _updateBurned(uint256 rAmount, uint256 tAmount) private {
        totalBurned += rAmount;
        _rOwned[address(0)] += rAmount;

        if (_isExcluded[address(0)]) {
            _tOwned[address(0)] += tAmount;
        }
    }

    function _updateTeam(uint256 rAmount, uint256 tAmount) private {
        _rOwned[_teamAddress] += rAmount;
        if (_isExcluded[_teamAddress]) {
            _tOwned[_teamAddress] += tAmount;
        }
    }

    function _reflectFee(uint256 rFee, uint256 tFee) private {
        uint256 rBurnAmt = (rFee * burnTaxFeePercentage) / 100; //80% of totalTaxed burned
        uint256 tBurnAmt = (tFee * burnTaxFeePercentage) / 100; //80% of totalTaxed burned
        _updateBurned(rBurnAmt, tBurnAmt);

        uint256 rTeamAmt = (rFee * teamTaxFeePercentage) / 100; //10% of totalTaxed to team
        uint256 tTeamAmt = (tFee * teamTaxFeePercentage) / 100; //10% of totalTaxed to team
        _updateTeam(rTeamAmt, tTeamAmt);

        uint256 holderAmt = rFee - (rBurnAmt + rTeamAmt); //10% of totalTaxed to holder
        _rTotal = _rTotal.sub(holderAmt);
        _tFeeTotal = _tFeeTotal.add(tFee);
    }

    function _getValues(uint256 tAmount)
        private
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        (uint256 tTransferAmount, uint256 tFee) = _getTValues(tAmount);
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(
            tAmount,
            tFee,
            _getRate()
        );
        return (
            rAmount,
            rTransferAmount,
            rFee,
            tTransferAmount,
            tFee
            //tLiquidity
        );
    }

    function _getTValues(uint256 tAmount)
        private
        view
        returns (uint256, uint256)
    //uint256
    {
        uint256 tFee = calculateTaxFee(tAmount);
        //uint256 tLiquidity = calculateLiquidityFee(tAmount);
        uint256 tTransferAmount = tAmount.sub(tFee); //.sub(tLiquidity);
        return (tTransferAmount, tFee); //, tLiquidity);
    }

    function _getRValues(
        uint256 tAmount,
        uint256 tFee,
        //uint256 tLiquidity,
        uint256 currentRate
    )
        private
        pure
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 rAmount = tAmount.mul(currentRate);
        uint256 rFee = tFee.mul(currentRate);
        //uint256 rLiquidity = tLiquidity.mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(rFee); //.sub(rLiquidity);
        return (rAmount, rTransferAmount, rFee);
    }

    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns (uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (
                _rOwned[_excluded[i]] > rSupply ||
                _tOwned[_excluded[i]] > tSupply
            ) return (_rTotal, _tTotal);
            rSupply = rSupply.sub(_rOwned[_excluded[i]]);
            tSupply = tSupply.sub(_tOwned[_excluded[i]]);
        }
        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    function claimTokens() public onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    function calculateTaxFee(uint256 _amount) private view returns (uint256) {
        return _amount.mul(_taxFee).div(10**2);
    }

    function removeAllFee() private {
        if (_taxFee == 0) return;

        _previousTaxFee = _taxFee;

        _taxFee = 0;
    }

    function restoreAllFee() private {
        _taxFee = _previousTaxFee;
    }

    function isExcludedFromFee(address account) public view returns (bool) {
        return _isExcludedFromFee[account];
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        //indicates if fee should be deducted from transfer
        bool takeFee = true;

        //if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromFee[from] || _isExcludedFromFee[to]) {
            takeFee = false;
        }

        //transfer amount, it will take tax, burn, liquidity fee
        _tokenTransfer(from, to, amount, takeFee);
    }

    //this method is responsible for taking all fee, if takeFee is true
    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 amount,
        bool takeFee
    ) private {
        if (!takeFee) removeAllFee();

        if (_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferFromExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && _isExcluded[recipient]) {
            _transferToExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferStandard(sender, recipient, amount);
        } else if (_isExcluded[sender] && _isExcluded[recipient]) {
            _transferBothExcluded(sender, recipient, amount);
        } else {
            _transferStandard(sender, recipient, amount);
        }

        if (!takeFee) restoreAllFee();
    }

    function _transferStandard(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee
        ) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferToExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee
        ) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferFromExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee
        ) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferBothExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee
        ) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function signers() external view returns (address[] memory) {
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

    function mint(uint256 amount) public virtual onlyController {
        //multiple transfers to different node contracts
        uint256 pools = (amount * 90) / 100;
        uint256 teamFees = amount - pools;
        uint256 nodesAmt = (pools * 30) / 100;
        uint256 stackAmt = (pools * 40) / 100;
        uint256 gameChangerAmt = (pools * 20) / 100;
        uint256 farmingPoolAmt = pools - nodesAmt - stackAmt - gameChangerAmt;

        _transfer(address(this), _team2Address, teamFees);

        _transfer(address(this), address(nodeControllerContract), nodesAmt);
        _afterTokenTransfer(address(nodeControllerContract), nodesAmt);

        _transfer(address(this), address(stackingControllerContract), stackAmt);
        _afterTokenTransfer(address(stackingControllerContract), stackAmt);

        _transfer(address(this), _gameChangerAddress, gameChangerAmt);

        _transfer(address(this), _farmingPoolAddress, farmingPoolAmt);
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

    function setNodeControllerContract(address _nodeControllerContract)
        external
        onlyOwner
    {
        nodeControllerContract = _nodeControllerContract;
    }

    function setStackingControllerContract(address _stackingControllerContract)
        external
        onlyOwner
    {
        stackingControllerContract = _stackingControllerContract;
    }

    function setFarmingPoolContract(address _farmingPoolContract)
        external
        onlyOwner
    {
        _farmingPoolAddress = _farmingPoolContract;
    }
}
