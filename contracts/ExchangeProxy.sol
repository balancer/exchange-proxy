pragma solidity ^0.5.11;
pragma experimental ABIEncoderV2;


// DO NOT USE ON MAINNET
// This contract is under development and tokens can easily get stuck forever

contract PoolInterface {
    function swap_ExactAmountIn(address, uint, address, uint, uint) external returns (uint, uint);
    function swap_ExactAmountOut(address, uint, address, uint, uint) external returns (uint, uint);
}

contract TokenInterface {
    function balanceOf(address) public returns (uint);
    function allowance(address, address) public returns (uint);
    function approve(address, uint) public returns (bool);
    function transfer(address,uint) public returns (bool);
    function transferFrom(address, address, uint) public returns (bool);
    function deposit() public payable;
    function withdraw(uint) public;
}

contract ExchangeProxy {

    struct Swap {
        address pool;
        uint    tokenInParam; // tokenInAmount / maxAmountIn / limitAmountIn
        uint    tokenOutParam; // minAmountOut / tokenAmountOut / limitAmountOut
        uint    maxPrice;
    }

    function add(uint a, uint b) internal pure returns (uint) {
        uint c = a + b;
        require(c >= a, "ERR_ADD_OVERFLOW");
        return c;
    }

    // Needs to be public. ABIEncoderV2 does not support external functions
    // TODO - check totalAmountOut > minTotalAmountOut
    // TODO - consider if function should revert if not all trades execute
    function batchSwapExactIn(
        Swap[] memory swaps,
        address tokenIn,
        address tokenOut,
        uint totalAmountIn,
        uint minTotalAmountOut
    )   
        public
        returns (uint totalAmountOut)
    {
        TokenInterface TI = TokenInterface(tokenIn);
        TokenInterface TO = TokenInterface(tokenOut);
        TI.transferFrom(msg.sender, address(this), totalAmountIn);
        totalAmountOut = 0;
        for (uint i = 0; i < swaps.length; i++) {
            Swap memory swap = swaps[i];
            
            PoolInterface pool = PoolInterface(swap.pool);
            if (TI.allowance(address(this), swap.pool) < totalAmountIn) {
                TI.approve(swap.pool, uint(-1));
            }
            (uint tokenAmountOut, uint spotPriceTarget) = pool.swap_ExactAmountIn(tokenIn, swap.tokenInParam, tokenOut, swap.tokenOutParam, swap.maxPrice);
            totalAmountOut = add(tokenAmountOut, totalAmountOut);
        }
        TO.transfer(msg.sender, totalAmountOut);
        return totalAmountOut;
    }

    // Needs to be public. ABIEncoderV2 does not support external functions
    // TODO - consider if function should revert if not all trades execute
    function batchSwapExactOut(
        Swap[] memory swaps,
        address tokenIn,
        address tokenOut,
        uint totalAmountOut,
        uint maxTotalAmountIn  
    )
        public
        returns (uint totalAmountIn)
    {
        TokenInterface TI = TokenInterface(tokenIn);
        TokenInterface TO = TokenInterface(tokenOut);
        TI.transferFrom(msg.sender, address(this), maxTotalAmountIn);
        totalAmountIn = 0;
        for (uint i = 0; i < swaps.length; i++) {
            Swap memory swap = swaps[i];
            PoolInterface pool = PoolInterface(swap.pool);
            if (TI.allowance(address(this), swap.pool) < maxTotalAmountIn) {
                TI.approve(swap.pool, uint(-1));
            }
            (uint tokenAmountIn, uint spotPriceTarget) = pool.swap_ExactAmountOut(tokenIn, swap.tokenInParam, tokenOut, swap.tokenOutParam, swap.maxPrice);
            totalAmountIn = add(tokenAmountIn, totalAmountIn);
        }
        TO.transfer(msg.sender, totalAmountOut);
        TI.transfer(msg.sender, TI.balanceOf(address(this)));
        return totalAmountIn;
    }

    // TODO
    function batchEthInSwapExactIn () public payable {}
    function batchEthOutSwapExactIn () public {}
    function batchEthInSwapExactOut () public payable {}
    function batchEthOutSwapExactOut () public {}
}