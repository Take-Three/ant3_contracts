// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

/**
 * @title TokenMintERC20Token
 * @author TokenMint (visit https://tokenmint.io)
 *
 * @dev Standard ERC20 token with burning and optional functions implemented.
 * For full specification of ERC-20 standard see:
 * https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20.md
 */

contract TokenMintERC20Token is ERC20Upgradeable {
    string private _name;
    string private _symbol;
    uint8 private _decimals;
    address private _tokenOwnerAddress;

    /**
     * @dev Constructor.
     * @param name name of the token
     * @param symbol symbol of the token, 3-4 chars is recommended
     * @param decimals number of decimal places of one token unit, 18 is widely used
     * @param totalSupply total supply of tokens in lowest units (depending on decimals)
     * @param tokenOwnerAddress address that gets 100% of token supply
     */
    function initialize(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 totalSupply,
        address tokenOwnerAddress
    ) public initializer {
        __ERC20_init(name, symbol);
        _name = name;
        _symbol = symbol;
        _decimals = decimals;
        _tokenOwnerAddress = tokenOwnerAddress;
        totalSupply = totalSupply * 10**decimals;
        // set tokenOwnerAddress as owner of all tokens
        _mint(tokenOwnerAddress, totalSupply);
    }

    /**
     * @dev Burns a specific amount of tokens.
     * @param value The amount of lowest token units to be burned.
     */
    function burn(uint256 value) public {
        _burn(msg.sender, value);
    }

    function getTokenOwnerAddress() public view returns (address) {
        return _tokenOwnerAddress;
    }
}
