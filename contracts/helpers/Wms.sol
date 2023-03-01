// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface IUniswapV2Pair {
    function balanceOf(address owner) external view returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );
}

contract Wms is Initializable, OwnableUpgradeable {
	
	uint256 public constant MAX_DECIMALS = 18;
	
    function initialize() public initializer {
        __Ownable_init();
	}
	
	function getPrice(IUniswapV2Pair[] calldata pairs, uint256[] calldata otDecimals,  IERC20Upgradeable stableToken, uint256 stDecimal) public view returns(uint256[] memory){
		uint256[] memory tokenPrices = new uint256[](pairs.length);
		
		for(uint256 i=0; i<pairs.length; i++) {
		
			if (address(pairs[i]) == address(0)) {
				tokenPrices[i] = 1e18; //1 usdt = 1 usdt :)
			} else {
				uint256 usdBalance;
				uint256 otherBalance;
				uint256 otDecimal = otDecimals[i];
				
				if (pairs[i].token0() == address(stableToken)) {
					(usdBalance, otherBalance , ) = pairs[i].getReserves();   
				}  else{
					(otherBalance, usdBalance , ) = pairs[i].getReserves();           
				}
				
				uint256 newUsdBalance = usdBalance * (10 ** (MAX_DECIMALS - stDecimal));
				uint256 newOtherBalance = otherBalance * (10 ** (MAX_DECIMALS - otDecimal));

				tokenPrices[i] = (newUsdBalance*1e18) / newOtherBalance;
			}
		}
		
        return tokenPrices;
    }

    function getBalances(IERC20Upgradeable[] calldata tokens, address[] calldata addresses) external view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](addresses.length * tokens.length);
		
		uint256 k = 0;
		
		for (uint256 j=0; j < addresses.length; j++) {
			for(uint256 i=0; i < tokens.length; i++) {
				uint256 bal = 0;
				if (tokens[i] == IERC20Upgradeable(address(0))) {
					bal = addresses[j].balance;
				} else {
					bal = tokens[i].balanceOf(addresses[j]);
				}
				
				if (bal > 0) {
					balances[k] = bal;
				} else {
					balances[k] = 2**256 - 1;
				}
				
				k++;
			}
		}

        return balances;        

    }
	
    //not accept eth deposit
    receive() external payable{
        revert();
    }

    fallback() external payable{
        revert();
    }
    
}