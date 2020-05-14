// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity 0.5.12;
pragma experimental ABIEncoderV2;


contract PoolInterface {
    function swapExactAmountIn(address, uint, address, uint, uint) external returns (uint, uint);
    function swapExactAmountOut(address, uint, address, uint, uint) external returns (uint, uint);
    function calcInGivenOut(uint, uint, uint, uint, uint, uint) public pure returns (uint);
    function getDenormalizedWeight(address) external view returns (uint);
    function getBalance(address) external view returns (uint);
    function getSwapFee() external view returns (uint);
}

contract TokenInterface {
    function balanceOf(address) public returns (uint);
    function allowance(address, address) public returns (uint);
    function approve(address, uint) public returns (bool);
    function transfer(address, uint) public returns (bool);
    function transferFrom(address, address, uint) public returns (bool);
    function deposit() public payable;
    function withdraw(uint) public;
}

contract ExchangeProxy {

    struct LegacySwap {
        address pool;
        uint    tokenInParam; // tokenInAmount / maxAmountIn / limitAmountIn
        uint    tokenOutParam; // minAmountOut / tokenAmountOut / limitAmountOut
        uint    maxPrice;
    }

    struct Swap {
        address pool;
        address tokenIn;
        address tokenOut;
        uint    swapAmount; // tokenInAmount / tokenOutAmount  
        uint    limitReturnAmount; // minAmountOut / maxAmountIn
        uint    maxPrice;
    }

    event LOG_CALL(
        bytes4  indexed sig,
        address indexed caller,
        bytes           data
    ) anonymous;

    modifier _logs_() {
        emit LOG_CALL(msg.sig, msg.sender, msg.data);
        _;
    }

    TokenInterface weth;
    address WETH;

    constructor(address _weth) public {
        weth = TokenInterface(_weth);
        WETH = _weth;
    }

    function add(uint a, uint b) internal pure returns (uint) {
        uint c = a + b;
        require(c >= a, "ERR_ADD_OVERFLOW");
        return c;
    }

    function multihopBatchSwapExactIn(
        Swap[][] memory swapSequences,
        address tokenIn,
        address tokenOut,
        uint totalAmountIn,
        uint minTotalAmountOut
    )   
        public
        _logs_
        returns (uint totalAmountOut)
    {
        TokenInterface TI = TokenInterface(tokenIn);
        TokenInterface TO = TokenInterface(tokenOut);
        require(TI.transferFrom(msg.sender, address(this), totalAmountIn), "ERR_TRANSFER_FAILED");

        totalAmountOut = multihopBatchSwapExactInCore(
            swapSequences
        );  

        require(totalAmountOut >= minTotalAmountOut, "ERR_LIMIT_OUT");

        uint TOBalance = TO.balanceOf(address(this));
        if(TOBalance>0)
            require(TO.transfer(msg.sender, TOBalance), "ERR_TRANSFER_FAILED");


        uint TIBalance = TI.balanceOf(address(this));
        if(TIBalance>0)
            require(TI.transfer(msg.sender, TIBalance), "ERR_TRANSFER_FAILED");

        return totalAmountOut;
    }

    function multihopBatchSwapExactInCore(
        Swap[][] memory swapSequences
    )   
        internal
        returns (uint totalAmountOut)
    {
        for (uint i = 0; i < swapSequences.length; i++) {
            uint tokenAmountOut;
            for (uint k = 0; k < swapSequences[i].length; k++) {
                Swap memory swap = swapSequences[i][k];
                TokenInterface SwapTokenIn = TokenInterface(swap.tokenIn);
                if(k==1)
                    // Makes sure that on the second swap the output of the first was used 
                    // so there is not intermediate token leftover
                    swap.swapAmount = tokenAmountOut;
                
                
                PoolInterface pool = PoolInterface(swap.pool); 
                if (SwapTokenIn.allowance(address(this), swap.pool) < swap.swapAmount) {
                    SwapTokenIn.approve(swap.pool, uint(-1));
                }
                (tokenAmountOut,) = pool.swapExactAmountIn(
                                            swap.tokenIn,
                                            swap.swapAmount,
                                            swap.tokenOut,
                                            swap.limitReturnAmount,
                                            swap.maxPrice
                                        );
            }
            // This takes the amountOut of the last swap 
            totalAmountOut = add(tokenAmountOut, totalAmountOut);
        }
        return totalAmountOut;
    }

    function multihopBatchSwapExactOut(
        Swap[][] memory swapSequences,
        address tokenIn,
        address tokenOut,
        uint maxTotalAmountIn
    )
        public
        _logs_
        returns (uint totalAmountIn)
    {
        TokenInterface TI = TokenInterface(tokenIn);
        TokenInterface TO = TokenInterface(tokenOut);
        require(TI.transferFrom(msg.sender, address(this), maxTotalAmountIn), "ERR_TRANSFER_FAILED");
        totalAmountIn = multihopBatchSwapExactOutCore(
            swapSequences
        );
        require(totalAmountIn <= maxTotalAmountIn, "ERR_LIMIT_IN");

        uint TOBalance = TO.balanceOf(address(this));
        if(TOBalance>0)
            require(TO.transfer(msg.sender, TOBalance), "ERR_TRANSFER_FAILED");

        uint TIBalance = TI.balanceOf(address(this));
        if(TIBalance>0)
            require(TI.transfer(msg.sender, TIBalance), "ERR_TRANSFER_FAILED");

        return totalAmountIn;
    }

    function multihopBatchSwapExactOutCore(
        Swap[][] memory swapSequences
    )
        internal
        returns (uint totalAmountIn)
    {
        for (uint i = 0; i < swapSequences.length; i++) {
            uint tokenAmountInFirstSwap;
            // Specific code for a simple swap and a multihop (2 swaps in sequence)
            if(swapSequences[i].length == 1){
                Swap memory swap = swapSequences[i][0];
                TokenInterface SwapTokenIn = TokenInterface(swap.tokenIn);

                PoolInterface pool = PoolInterface(swap.pool);
                if (SwapTokenIn.allowance(address(this), swap.pool) < uint(-1)) { // We don't know in advance how much tokenIn will be needed
                    SwapTokenIn.approve(swap.pool, uint(-1));
                }

                (tokenAmountInFirstSwap,) = pool.swapExactAmountOut(
                                        swap.tokenIn,
                                        swap.limitReturnAmount,
                                        swap.tokenOut,
                                        swap.swapAmount,
                                        swap.maxPrice
                                    );
            }
            // Multihop (we assume swapSequences can only have 1 or 2 swaps)
            else{
                // Consider we are swapping A -> B and B -> C. The goal is to buy a given amount
                // of token C. But first we need to buy B with A so we can then buy C with B
                // To get the exact amount of C we then first need to calculate how much B we'll need:
                uint intermediateTokenAmount; // This would be token B as described above
                Swap memory secondSwap = swapSequences[i][1];
                PoolInterface poolSecondSwap = PoolInterface(secondSwap.pool);
                intermediateTokenAmount = poolSecondSwap.calcInGivenOut(
                                        poolSecondSwap.getBalance(secondSwap.tokenIn),
                                        poolSecondSwap.getDenormalizedWeight(secondSwap.tokenIn),
                                        poolSecondSwap.getBalance(secondSwap.tokenOut),
                                        poolSecondSwap.getDenormalizedWeight(secondSwap.tokenOut),
                                        secondSwap.swapAmount,
                                        poolSecondSwap.getSwapFee()
                                    );

                //// Buy intermediateTokenAmount of token B with A in the first pool                
                Swap memory firstSwap = swapSequences[i][0];
                TokenInterface FirstSwapTokenIn = TokenInterface(firstSwap.tokenIn);
                PoolInterface poolFirstSwap = PoolInterface(firstSwap.pool);
                if (FirstSwapTokenIn.allowance(address(this), firstSwap.pool) < uint(-1)) { // We don't know in advance how much tokenIn will be needed
                    FirstSwapTokenIn.approve(firstSwap.pool, uint(-1));
                }

                (tokenAmountInFirstSwap,) = poolFirstSwap.swapExactAmountOut(
                                        firstSwap.tokenIn,
                                        firstSwap.limitReturnAmount,
                                        firstSwap.tokenOut,
                                        intermediateTokenAmount, // This is the amount of token B we need
                                        firstSwap.maxPrice
                                    );

                //// Buy the final amount of token C desired
                TokenInterface SecondSwapTokenIn = TokenInterface(secondSwap.tokenIn);
                if (SecondSwapTokenIn.allowance(address(this), secondSwap.pool) < uint(-1)) { // We don't know in advance how much tokenIn will be needed
                    SecondSwapTokenIn.approve(secondSwap.pool, uint(-1));
                }

                poolSecondSwap.swapExactAmountOut(
                                        secondSwap.tokenIn,
                                        secondSwap.limitReturnAmount,
                                        secondSwap.tokenOut,
                                        secondSwap.swapAmount, 
                                        secondSwap.maxPrice
                                    );
            }
            totalAmountIn = add(tokenAmountInFirstSwap, totalAmountIn);
        }
        return totalAmountIn;
    }

    function multihopBatchEthInSwapExactIn(
        Swap[][] memory swapSequences,
        address tokenOut,
        uint minTotalAmountOut
    )
        public payable
        _logs_
        returns (uint totalAmountOut)
    {
        TokenInterface TO = TokenInterface(tokenOut);
        weth.deposit.value(msg.value)();

        totalAmountOut = multihopBatchSwapExactInCore(
            swapSequences
        );
        require(totalAmountOut >= minTotalAmountOut, "ERR_LIMIT_OUT");

        uint TOBalance = TO.balanceOf(address(this));
        if(TOBalance>0)
            require(TO.transfer(msg.sender, TOBalance), "ERR_TRANSFER_FAILED");

        uint wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            weth.withdraw(wethBalance);
            (bool xfer,) = msg.sender.call.value(wethBalance)("");
            require(xfer, "ERR_ETH_FAILED");
        }

        return totalAmountOut;

    }

    function multihopBatchEthOutSwapExactIn(
        Swap[][] memory swapSequences,
        address tokenIn,
        uint totalAmountIn,
        uint minTotalAmountOut
    )
        public
        _logs_
        returns (uint totalAmountOut)
    {
        TokenInterface TI = TokenInterface(tokenIn);
        require(TI.transferFrom(msg.sender, address(this), totalAmountIn), "ERR_TRANSFER_FAILED");
        
        // TODO: should we pass TI and TO to avoid loading costs in batchSwapExactInCore again?
        totalAmountOut = multihopBatchSwapExactInCore(
            swapSequences
        );

        require(totalAmountOut >= minTotalAmountOut, "ERR_LIMIT_OUT");
        uint wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            weth.withdraw(wethBalance);
            (bool xfer,) = msg.sender.call.value(wethBalance)("");
            require(xfer, "ERR_ETH_FAILED");
        }

        uint TIBalance = TI.balanceOf(address(this));
        if(TIBalance>0)
            require(TI.transfer(msg.sender, TIBalance), "ERR_TRANSFER_FAILED");

        return totalAmountOut;
    }

    function multihopBatchEthInSwapExactOut(
        Swap[][] memory swapSequences,
        address tokenOut
    )
        public payable
        _logs_
        returns (uint totalAmountIn)
    {
        TokenInterface TO = TokenInterface(tokenOut);
        weth.deposit.value(msg.value)();

        totalAmountIn = multihopBatchSwapExactOutCore(
            swapSequences
        );

        require(TO.transfer(msg.sender, TO.balanceOf(address(this))), "ERR_TRANSFER_FAILED");
        
        uint wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            weth.withdraw(wethBalance);
            (bool xfer,) = msg.sender.call.value(wethBalance)("");
            require(xfer, "ERR_ETH_FAILED");
        }
        return totalAmountIn;
    }

    function multihopBatchEthOutSwapExactOut(
        Swap[][] memory swapSequences,
        address tokenIn,
        uint maxTotalAmountIn
    )
        public
        _logs_
        returns (uint totalAmountIn)
    {
        TokenInterface TI = TokenInterface(tokenIn);
        require(TI.transferFrom(msg.sender, address(this), maxTotalAmountIn), "ERR_TRANSFER_FAILED");
        totalAmountIn = multihopBatchSwapExactOutCore(
            swapSequences
        );
        require(totalAmountIn <= maxTotalAmountIn, "ERR_LIMIT_IN");

        uint TIBalance = TI.balanceOf(address(this));
        if(TIBalance>0)
            require(TI.transfer(msg.sender, TIBalance), "ERR_TRANSFER_FAILED");
            
        uint wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            weth.withdraw(wethBalance);
            (bool xfer,) = msg.sender.call.value(wethBalance)("");
            require(xfer, "ERR_ETH_FAILED");
        }
        return totalAmountIn;
    }

    // Functions of previous exchange-proxy for backward compatibility

    function batchSwapExactIn(
        LegacySwap[] memory swaps,
        address tokenIn,
        address tokenOut,
        uint totalAmountIn,
        uint minTotalAmountOut
    )   
        public
        _logs_
        returns (uint totalAmountOut)
    {
        TokenInterface TI = TokenInterface(tokenIn);
        TokenInterface TO = TokenInterface(tokenOut);
        require(TI.transferFrom(msg.sender, address(this), totalAmountIn), "ERR_TRANSFER_FAILED");
        for (uint i = 0; i < swaps.length; i++) {
            LegacySwap memory swap = swaps[i];
            
            PoolInterface pool = PoolInterface(swap.pool);
            if (TI.allowance(address(this), swap.pool) < totalAmountIn) {
                TI.approve(swap.pool, uint(-1));
            }
            (uint tokenAmountOut,) = pool.swapExactAmountIn(
                                        tokenIn,
                                        swap.tokenInParam,
                                        tokenOut,
                                        swap.tokenOutParam,
                                        swap.maxPrice
                                    );
            totalAmountOut = add(tokenAmountOut, totalAmountOut);
        }
        require(totalAmountOut >= minTotalAmountOut, "ERR_LIMIT_OUT");
        uint TOBalance = TO.balanceOf(address(this));
        if(TOBalance>0)
            require(TO.transfer(msg.sender, TOBalance), "ERR_TRANSFER_FAILED");

        uint TIBalance = TI.balanceOf(address(this));
        if(TIBalance>0)
            require(TI.transfer(msg.sender, TIBalance), "ERR_TRANSFER_FAILED");
        
        return totalAmountOut;
    }

    function batchSwapExactOut(
        LegacySwap[] memory swaps,
        address tokenIn,
        address tokenOut,
        uint maxTotalAmountIn
    )
        public
        _logs_
        returns (uint totalAmountIn)
    {
        TokenInterface TI = TokenInterface(tokenIn);
        TokenInterface TO = TokenInterface(tokenOut);
        require(TI.transferFrom(msg.sender, address(this), maxTotalAmountIn), "ERR_TRANSFER_FAILED");
        for (uint i = 0; i < swaps.length; i++) {
            LegacySwap memory swap = swaps[i];
            PoolInterface pool = PoolInterface(swap.pool);
            if (TI.allowance(address(this), swap.pool) < maxTotalAmountIn) {
                TI.approve(swap.pool, uint(-1));
            }
            (uint tokenAmountIn,) = pool.swapExactAmountOut(
                                        tokenIn,
                                        swap.tokenInParam,
                                        tokenOut,
                                        swap.tokenOutParam,
                                        swap.maxPrice
                                    );
            totalAmountIn = add(tokenAmountIn, totalAmountIn);
        }
        require(totalAmountIn <= maxTotalAmountIn, "ERR_LIMIT_IN");

        uint TOBalance = TO.balanceOf(address(this));
        if(TOBalance>0)
            require(TO.transfer(msg.sender, TOBalance), "ERR_TRANSFER_FAILED");

        uint TIBalance = TI.balanceOf(address(this));
        if(TIBalance>0)
            require(TI.transfer(msg.sender, TIBalance), "ERR_TRANSFER_FAILED");
        return totalAmountIn;
    }

    function batchEthInSwapExactIn(
        LegacySwap[] memory swaps,
        address tokenOut,
        uint minTotalAmountOut
    )
        public payable
        _logs_
        returns (uint totalAmountOut)
    {
        TokenInterface TO = TokenInterface(tokenOut);
        weth.deposit.value(msg.value)();
        for (uint i = 0; i < swaps.length; i++) {
            LegacySwap memory swap = swaps[i];
            PoolInterface pool = PoolInterface(swap.pool);
            if (weth.allowance(address(this), swap.pool) < msg.value) {
                weth.approve(swap.pool, uint(-1));
            }
            (uint tokenAmountOut,) = pool.swapExactAmountIn(
                                        address(weth),
                                        swap.tokenInParam,
                                        tokenOut,
                                        swap.tokenOutParam,
                                        swap.maxPrice
                                    );
            totalAmountOut = add(tokenAmountOut, totalAmountOut);
        }
        require(totalAmountOut >= minTotalAmountOut, "ERR_LIMIT_OUT");
        uint TOBalance = TO.balanceOf(address(this));
        if(TOBalance>0)
            require(TO.transfer(msg.sender, TOBalance), "ERR_TRANSFER_FAILED");
        uint wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            weth.withdraw(wethBalance);
            (bool xfer,) = msg.sender.call.value(wethBalance)("");
            require(xfer, "ERR_ETH_FAILED");
        }
        return totalAmountOut;
    }

    function batchEthOutSwapExactIn(
        LegacySwap[] memory swaps,
        address tokenIn,
        uint totalAmountIn,
        uint minTotalAmountOut
    )
        public
        _logs_
        returns (uint totalAmountOut)
    {
        TokenInterface TI = TokenInterface(tokenIn);
        require(TI.transferFrom(msg.sender, address(this), totalAmountIn), "ERR_TRANSFER_FAILED");
        for (uint i = 0; i < swaps.length; i++) {
            LegacySwap memory swap = swaps[i];
            PoolInterface pool = PoolInterface(swap.pool);
            if (TI.allowance(address(this), swap.pool) < totalAmountIn) {
                TI.approve(swap.pool, uint(-1));
            }
            (uint tokenAmountOut,) = pool.swapExactAmountIn(
                                        tokenIn,
                                        swap.tokenInParam,
                                        address(weth),
                                        swap.tokenOutParam,
                                        swap.maxPrice
                                    );

            totalAmountOut = add(tokenAmountOut, totalAmountOut);
        }
        require(totalAmountOut >= minTotalAmountOut, "ERR_LIMIT_OUT");
        
        uint wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            weth.withdraw(wethBalance);
            (bool xfer,) = msg.sender.call.value(wethBalance)("");
            require(xfer, "ERR_ETH_FAILED");
        }

        uint TIBalance = TI.balanceOf(address(this));
        if(TIBalance>0)
            require(TI.transfer(msg.sender, TIBalance), "ERR_TRANSFER_FAILED");
        return totalAmountOut;
    }

    function batchEthInSwapExactOut(
        LegacySwap[] memory swaps,
        address tokenOut
    )
        public payable
        _logs_
        returns (uint totalAmountIn)
    {
        TokenInterface TO = TokenInterface(tokenOut);
        weth.deposit.value(msg.value)();
        for (uint i = 0; i < swaps.length; i++) {
            LegacySwap memory swap = swaps[i];
            PoolInterface pool = PoolInterface(swap.pool);
            if (weth.allowance(address(this), swap.pool) < msg.value) {
                weth.approve(swap.pool, uint(-1));
            }
            (uint tokenAmountIn,) = pool.swapExactAmountOut(
                                        address(weth),
                                        swap.tokenInParam,
                                        tokenOut,
                                        swap.tokenOutParam,
                                        swap.maxPrice
                                    );

            totalAmountIn = add(tokenAmountIn, totalAmountIn);
        }
        uint TOBalance = TO.balanceOf(address(this));
        if(TOBalance>0)
            require(TO.transfer(msg.sender, TOBalance), "ERR_TRANSFER_FAILED");

            uint wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            weth.withdraw(wethBalance);
            (bool xfer,) = msg.sender.call.value(wethBalance)("");
            require(xfer, "ERR_ETH_FAILED");
        }
        return totalAmountIn;
    }

    function batchEthOutSwapExactOut(
        LegacySwap[] memory swaps,
        address tokenIn,
        uint maxTotalAmountIn
    )
        public
        _logs_
        returns (uint totalAmountIn)
    {
        TokenInterface TI = TokenInterface(tokenIn);
        require(TI.transferFrom(msg.sender, address(this), maxTotalAmountIn), "ERR_TRANSFER_FAILED");
        for (uint i = 0; i < swaps.length; i++) {
            LegacySwap memory swap = swaps[i];
            PoolInterface pool = PoolInterface(swap.pool);
            if (TI.allowance(address(this), swap.pool) < maxTotalAmountIn) {
                TI.approve(swap.pool, uint(-1));
            }
            (uint tokenAmountIn,) = pool.swapExactAmountOut(
                                        tokenIn,
                                        swap.tokenInParam,
                                        address(weth),
                                        swap.tokenOutParam,
                                        swap.maxPrice
                                    );

            totalAmountIn = add(tokenAmountIn, totalAmountIn);
        }
        require(totalAmountIn <= maxTotalAmountIn, "ERR_LIMIT_IN");

        uint TIBalance = TI.balanceOf(address(this));
        if(TIBalance>0)
            require(TI.transfer(msg.sender, TIBalance), "ERR_TRANSFER_FAILED");

        uint wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) {
            weth.withdraw(wethBalance);
            (bool xfer,) = msg.sender.call.value(wethBalance)("");
            require(xfer, "ERR_ETH_FAILED");
        }
        return totalAmountIn;
    }

    function() external payable {}
}