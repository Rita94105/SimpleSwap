// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ISimpleSwap } from "./interface/ISimpleSwap.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract SimpleSwap is ISimpleSwap, ERC20 {
    // Implement core logic here
    address public tokenA;
    address public tokenB;
    uint256 public reserveA;
    uint256 public reserveB;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);

    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "SimpleSwap: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    constructor(address _tokenA, address _tokenB) ERC20("SimpleSwap", "SSW") {
        //check constructor_tokenA_is_not_a_contract_address
        require(iscontract(_tokenA), "SimpleSwap: TOKENA_IS_NOT_CONTRACT");
        //check constructor_tokenB_is_not_a_contract_address
        require(iscontract(_tokenB), "SimpleSwap: TOKENB_IS_NOT_CONTRACT");
        //check constructor_tokenA_tokenB_identical_address
        require(_tokenA != _tokenB, "SimpleSwap: TOKENA_TOKENB_IDENTICAL_ADDRESS");
        //constructor_should_be_zero_after_initialize
        reserveA = 0;
        reserveB = 0;
        //tokenA_should_be_less_than_tokenB
        if (uint256(uint160(_tokenA)) > uint256(uint160(_tokenB))) {
            tokenA = _tokenB;
            tokenB = _tokenA;
        } else {
            tokenA = _tokenA;
            tokenB = _tokenB;
        }
    }

    function getReserves() external view override returns (uint256 _reserveA, uint256 _reserveB){
        _reserveA = reserveA;
        _reserveB = reserveB;
    }

    function getTokenA() external view override returns (address _tokenA){
        _tokenA = tokenA;
    }

    function getTokenB() external view override returns (address _tokenB){
        _tokenB = tokenB;
    }

    function iscontract(address _addr) private view returns (bool){
        uint256 length;
        assembly {
            length := extcodesize(_addr)
        }
        return (length > 0);
    }
    
    function swap(address tokenIn, address tokenOut, uint256 amountIn) external virtual override returns (uint256 amountOut){
        //revert_when_tokenIn_is_not_tokenA_or_tokenB
        require(tokenIn == tokenA || tokenIn == tokenB, "SimpleSwap: INVALID_TOKEN_IN");
        //revert_when_tokenOut_is_not_tokenA_or_tokenB
        require(tokenOut == tokenA || tokenOut == tokenB, "SimpleSwap: INVALID_TOKEN_OUT");
        //when_tokenIn_is_the_same_as_tokenOut
        require(tokenIn != tokenOut, "SimpleSwap: IDENTICAL_ADDRESS");
        //when_amountIn_is_zero
        require(amountIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");
        //calculate amountOut
        uint256 reserveIn = tokenIn == tokenA ? reserveA : reserveB;
        uint256 reserveOut = tokenOut == tokenA ? reserveA : reserveB;
        amountOut = amountIn * reserveOut / (reserveIn + amountIn);
        //revert_when_amountOut_is_zero
        require(amountOut > 0, "SimpleSwap: INSUFFICIENT_OUTPUT_AMOUNT");
        //revert_when_amountOut_is_more_than_reserveOut
        require(amountOut <= reserveOut, "SimpleSwap: INSUFFICIENT_LIQUIDITY");
        //transfer tokenIn to this contract
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        //transfer tokenOut to msg.sender
        IERC20(tokenOut).transfer(msg.sender, amountOut);
        //update reserveA and reserveB
        if(tokenIn == tokenA){
            reserveA += amountIn;
            reserveB -= amountOut;
        } else {
            reserveA -= amountOut;
            reserveB += amountIn;
        }
        //get balanceA and balanceB
        uint256 balanceA = IERC20(tokenA).balanceOf(address(this));
        uint256 balanceB = IERC20(tokenB).balanceOf(address(this));
        //check x*y=k
        require(balanceA * balanceB == reserveA * reserveB, "SimpleSwap: K");
        _update(balanceA, balanceB);
        emit Swap(msg.sender,tokenIn, tokenOut, amountIn, amountOut);
    }

    function addLiquidity(
        uint256 amountAIn,
        uint256 amountBIn
    ) external virtual override returns (uint256 _amountA, uint256 _amountB, uint256 liquidity){
        //revert when_tokenA_amount_is_zero
        require(amountAIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");
        //revert when_tokenB_amount_is_zero
        require(amountBIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");
        // calculate liquidity
        (_amountA, _amountB) = _addLiquidity(amountAIn, amountBIn);
        emit AddLiquidity(msg.sender, _amountA, _amountB, liquidity);
        //transfer tokenA to this contract
        IERC20(tokenA).transferFrom(msg.sender, address(this), _amountA);
        //transfer tokenB to this contract
        IERC20(tokenB).transferFrom(msg.sender, address(this), _amountB);
        //mint liquidity to msg.sender
        liquidity = mint(msg.sender);
        emit AddLiquidity(msg.sender, _amountA, _amountB, liquidity);
    }

    function removeLiquidity(uint256 liquidity) external virtual override returns (uint256 _amountA, uint256 _amountB){
        //revert_removeLiquidity_when_lp_token_balance_is_zero
        require(liquidity > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_BURNED");
        _transfer(msg.sender, address(this), liquidity);
        (_amountA, _amountB) = burn(msg.sender);
        emit RemoveLiquidity(msg.sender, _amountA, _amountB, liquidity);
    }

    function mint(address _to) internal lock returns (uint liquidity) {
        uint balanceA = IERC20(tokenA).balanceOf(address(this));
        uint balanceB = IERC20(tokenB).balanceOf(address(this));
        uint amountA_ = balanceA - reserveA;
        uint amountB_ = balanceB - reserveB;

        uint _totalSupply = totalSupply(); // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amountA_ * amountB_);
        } else {
            liquidity = Math.min(amountA_ * _totalSupply / reserveA, amountB_ * _totalSupply / reserveB);
        }
        require(liquidity > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(_to, liquidity);
        _update(balanceA, balanceB);
        emit Mint(msg.sender, amountA_, amountB_);
    }

    function burn(address _to) internal lock returns (uint _amountA, uint _amountB) {
        uint balanceA = IERC20(tokenA).balanceOf(address(this));
        uint balanceB = IERC20(tokenB).balanceOf(address(this));
        uint liquidity = balanceOf(address(this));

        uint _totalSupply = totalSupply(); // gas savings, must be defined here since totalSupply can update in _mintFee
        _amountA = liquidity * balanceA / _totalSupply; // using balances ensures pro-rata distribution
        _amountB = liquidity * balanceB / _totalSupply; // using balances ensures pro-rata distribution
        require(_amountA > 0 && _amountB > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_BURNED");
        _burn(address(this), liquidity);
        _safeTransfer(tokenA, _to, _amountA);
        _safeTransfer(tokenB, _to, _amountB);
        balanceA = IERC20(tokenA).balanceOf(address(this));
        balanceB = IERC20(tokenB).balanceOf(address(this));

        _update(balanceA, balanceB);
        emit Burn(msg.sender, _amountA, _amountB, _to);
    }

    function quote(uint _amountA, uint _reserveA, uint _reserveB) internal pure returns (uint _amountB) {
        require(_amountA > 0, "SimpleSwap: INSUFFICIENT_AMOUNT");
        require(_reserveA > 0 && _reserveB > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY");
        _amountB = _amountA * _reserveB / _reserveA;
    }

    function _safeTransfer(address _token, address _to, uint _value) private {
        (bool success, bytes memory data) = _token.call(abi.encodeWithSelector(SELECTOR, _to, _value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "SimpleSwap: TRANSFER_FAILED");
    }
    function _addLiquidity(uint256 amountADesired, uint256 amountBDesired) internal virtual returns (uint256 _amountA, uint256 _amountB){
        if(reserveA == 0 && reserveB == 0){
            (_amountA, _amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = quote(amountADesired, reserveA, reserveB);
            if(amountBOptimal <= amountBDesired){
                require(amountBOptimal > 0, "SimpleSwap: INSUFFICIENT_B_AMOUNT");
                (_amountA, _amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal > 0, "SimpleSwap: INSUFFICIENT_A_AMOUNT");
                (_amountA, _amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function _update(uint balanceA, uint balanceB) private {
        reserveA = balanceA;
        reserveB = balanceB;
    }
}
