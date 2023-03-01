// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "./IPancakeswapV2Router.sol";
import "./IPancakePair.sol";

contract Oracle is Initializable, OwnableUpgradeable {
    IPancakeswapV2Router public pancakeswapV2Router;

    function initialize(address _pancakeswapRouter) public initializer {
        __Ownable_init();
        pancakeswapV2Router = IPancakeswapV2Router(_pancakeswapRouter);
    }

    function getTokenPrice(uint256 amountIn, address[] calldata path)
        public
        view
        returns (uint256[] memory)
    {
        uint256[] memory res = pancakeswapV2Router.getAmountsOut(
            amountIn,
            path
        );
        return res;
    }

    function getLpPrice(
        address lpToken,
        uint256 amount0In,
        address[] calldata reserve0path,
        uint256 amount1In,
        address[] calldata reserve1path
    ) public view returns (uint256) {
        uint112 reserve0;
        uint112 reserve1;
        uint32 blockTimestampLast;

        (reserve0, reserve1, blockTimestampLast) = IPancakePair(lpToken)
            .getReserves();
        uint256 totalSupply = IPancakePair(lpToken).totalSupply();
        uint256 reserve0dp = IPancakePair(reserve0path[0]).decimals();
        uint256 reserve1dp = IPancakePair(reserve1path[0]).decimals();

        uint256[] memory res0 = pancakeswapV2Router.getAmountsOut(
            amount0In,
            reserve0path
        );
        uint256 reserve0price = res0[reserve0path.length - 1];

        uint256[] memory res1 = pancakeswapV2Router.getAmountsOut(
            amount1In,
            reserve1path
        );
        uint256 reserve1price = res1[reserve1path.length - 1];

        uint256 totalLiquidity = (reserve0 *
            reserve0price *
            10**(18 - reserve0dp)) +
            (reserve1 * reserve1price * 10**(18 - reserve1dp));

        uint256 lpPrice = totalLiquidity / totalSupply;

        return lpPrice;
    }
}
