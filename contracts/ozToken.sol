// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;


import {
    ERC4626Upgradeable,  
    ERC20Upgradeable,
    MathUpgradeable,
    IERC20Upgradeable
} from "@openzeppelin/contracts-upgradeable-4.7.3/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable-4.7.3/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {ozIDiamond} from "./interfaces/ozIDiamond.sol";
import {AmountsIn, AmountsOut, Asset} from "./AppStorage.sol";
import {IERC20Permit} from "./interfaces/IERC20Permit.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable-4.7.3/token/ERC20/extensions/draft-IERC20PermitUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable-4.7.3/utils/cryptography/draft-EIP712Upgradeable.sol";
import {CountersUpgradeable} from "@openzeppelin/contracts-upgradeable-4.7.3/utils/CountersUpgradeable.sol";
import {ECDSAUpgradeable} from "@openzeppelin/contracts-upgradeable-4.7.3/utils/cryptography/ECDSAUpgradeable.sol";

import {AmountsIn} from "./AppStorage.sol";
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";
import {Helpers} from "./libraries/Helpers.sol";
import "./Errors.sol";

import "forge-std/console.sol";


error ozTokenInvalidMintReceiver(address account);


contract ozToken is IERC20MetadataUpgradeable, IERC20PermitUpgradeable, EIP712Upgradeable {

    using CountersUpgradeable for CountersUpgradeable.Counter;

    using FixedPointMathLib for uint;
    using Helpers for uint;

    address private _ozDiamond;
    address private _underlying;

    uint private _totalShares;
    uint private _totalAssets;

    mapping(address user => uint256 shares) private _shares;
    mapping(address => CountersUpgradeable.Counter) private _nonces;
    mapping(address => mapping(address => uint256)) private _allowances;

    // Token name
    string private _name;
    // Token Symbol
    string private _symbol;

    bytes32 private constant _PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    uint public FORMAT_DECIMALS;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address underlying_,
        address diamond_,
        string memory name_,
        string memory symbol_
    ) external initializer {
        _name = name_;
        _symbol = symbol_;
        _ozDiamond = diamond_;
        _underlying = underlying_;
        __EIP712_init(name_, "1");
        FORMAT_DECIMALS = IERC20Permit(underlying_).decimals() == 18 ? 1e12 : 1;
    }


    function name() public view returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }
    
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(msg.sender, spender, allowance(msg.sender, spender) + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = allowance(msg.sender, spender);
        if (currentAllowance < subtractedValue) revert OZError03();
        unchecked {
            _approve(msg.sender, spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private  {
        if (owner == address(0) || spender == address(0)) revert OZError04(owner, spender);
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) private {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < amount) revert OZError05(amount);
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    //-----------

    function _convertToShares(uint assets_) private view returns(uint) { 
        return assets_.mulDivUp(totalShares(), ozIDiamond(_ozDiamond).getUnderlyingValue());
    }

    function totalAssets() public view returns(uint) {
        return _totalAssets;
    }

    function totalShares() public view returns(uint) {
        return _totalShares;
    }

    function totalSupply() public view returns(uint) {
        return _totalShares == 0 ? 0 : _convertToAssets(_totalShares);
    }

    function sharesOf(address account_) public view returns(uint) {
        return _shares[account_];
    }

    function asset() public view returns(address) {
        return _underlying;
    }

    function balanceOf(address account_) public view returns(uint) {
        return convertToAssets(sharesOf(account_));
    }


    function mint(bytes memory data_) external returns(uint) { 
        (AmountsIn memory amounts, address receiver_) = abi.decode(data_, (AmountsIn, address));

        uint assets = amounts.amountIn.format(FORMAT_DECIMALS); 

        // require(assets <= maxDeposit(receiver_), "ERC4626: deposit more than max"); //<-- Not necessary , I think. Check
        //check this function when the time comes to decide if this is ERC4626

        ozIDiamond(_ozDiamond).useUnderlying(asset(), msg.sender, amounts); 

        uint shares = totalShares() == 0 ? assets : previewDeposit(assets);

        _totalAssets += assets;
        _totalShares += shares;

        unchecked {
            _shares[receiver_] += shares;
        }

        return shares;
    }
    //-------------


    function _convertToSharesFromUnderlying(uint assets_) private view returns(uint) {
        return assets_.mulDivDown(totalShares(), totalAssets());
    }

    function previewDeposit(uint assets_) public view returns(uint) {
        return _convertToSharesFromUnderlying(assets_);
    }

    function previewRedeem(uint shares_) public view returns(uint) {
        return _convertToAssetsFromUnderlying(shares_);
    }

    //remove this function if this is not ERC4626
    function maxDeposit(address) public view returns (uint256) {
        return _isVaultCollateralized() ? type(uint256).max : 0;
    }

    //...and this one
    function _isVaultCollateralized() private view returns (bool) { 
        return totalAssets() > 0 || totalSupply() == 0;
    }

    function convertToUnderlying(uint shares_) external view returns(uint amountUnderlying) {
        amountUnderlying = (shares_ * ozIDiamond(_ozDiamond).totalUnderlying(Asset.UNDERLYING)) / totalShares();
    }


    function redeem(bytes memory data_) external returns(uint) {
        (
            uint ozAmountIn,,,,
        ) = abi.decode(data_, (uint, uint, uint, uint, address));

        uint256 accountShares = sharesOf(msg.sender);
        uint shares = convertToShares(ozAmountIn);

        if (accountShares < shares) revert OZError06(msg.sender, accountShares, shares);

        uint assets = previewRedeem(shares);

        uint amountOut = ozIDiamond(_ozDiamond).useOzTokens(msg.sender, data_);

        accountShares = sharesOf(_ozDiamond);

        unchecked {
            _shares[_ozDiamond] = 0;
            _totalShares -= accountShares;
            _totalAssets -= assets;
        }

        return amountOut;
    }


    function _transfer(
        address from, 
        address to, 
        uint256 amount
    ) internal {
        if (from == address(0) || to == address(0)) revert OZError04(from, to);

        uint256 shares = convertToShares(amount);
        uint256 fromShares = _shares[from];

        if (fromShares < shares) revert OZError07(from, fromShares, shares);

        unchecked {
            _shares[from] = fromShares - shares;
            // Overflow not possible: the sum of all shares is capped by totalShares, and the sum is preserved by
            // decrementing then incrementing.
            _shares[to] += shares;
        }
    }

    function previewWithdraw(uint256 assets) public view returns (uint256) {
        return _convertToShares(assets); 
    }

   
    function _convertToAssets(uint256 shares_) private view returns (uint256 assets) {  
        return shares_.mulDivDown((ozIDiamond(_ozDiamond).getUnderlyingValue() / (totalShares() == 0 ? 1: totalShares())), 1);
    }

    function _convertToAssetsFromUnderlying(uint shares_) private view returns(uint){
        return shares_.mulDivDown(ozIDiamond(_ozDiamond).getUnderlyingValue(), totalSupply());
    }

    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        return _convertToAssets(shares);
    }

    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        return _convertToShares(assets);
    }


    //----------------------

    /**
     * @notice Returns the EIP-712 DOMAIN_SEPARATOR.
     * @return A bytes32 value representing the EIP-712 DOMAIN_SEPARATOR.
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /**
     * @notice Returns the current nonce for the given owner address.
     * @param owner The address whose nonce is to be retrieved.
     * @return The current nonce as a uint256 value.
     */
    function nonces(address owner) external view returns (uint256) {
        return _nonces[owner].current();
    }

    /**
     * @dev Private function that increments and returns the current nonce for a given owner address.
     * @param owner The address whose nonce is to be incremented.
     */
    function _useNonce(address owner) private returns (uint256 current) {
        CountersUpgradeable.Counter storage nonce = _nonces[owner];
        current = nonce.current();

        nonce.increment();
    }

    /**
     * @notice Allows an owner to approve a spender with a one-time signature, bypassing the need for a transaction.
     * @dev Uses the EIP-2612 standard.
     * @param owner The address of the token owner.
     * @param spender The address of the spender.
     * @param value The amount of tokens to be approved.
     * @param deadline The expiration time of the signature, specified as a Unix timestamp.
     * @param v The recovery byte of the signature.
     * @param r The first 32 bytes of the signature.
     * @param s_ The second 32 bytes of the signature.
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s_
    ) external {
        if (block.timestamp > deadline) revert OZError08(deadline, block.timestamp);

        bytes32 structHash = keccak256(abi.encode(_PERMIT_TYPEHASH, owner, spender, value, _useNonce(owner), deadline));
        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = ECDSAUpgradeable.recover(hash, v, r, s_);

        if (signer != owner) revert OZError09(owner, spender);

        _approve(owner, spender, value);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[42] private __gap;

}