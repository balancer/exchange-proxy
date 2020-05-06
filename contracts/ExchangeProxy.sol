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

    modifier _lock_() {
        require(!_mutex, "ERR_REENTRY");
        _mutex = true;
        _;
        _mutex = false;
    }

    bool private _mutex;
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

    function batchSwapExactIn(
        Swap[][] memory swapSequences,
        address tokenIn,
        address tokenOut,
        uint totalAmountIn,
        uint minTotalAmountOut
    )   
        public
        _logs_
        _lock_
        returns (uint totalAmountOut)
    {
        TokenInterface TI = TokenInterface(tokenIn);
        TokenInterface TO = TokenInterface(tokenOut);
        require(TI.transferFrom(msg.sender, address(this), totalAmountIn), "ERR_TRANSFER_FAILED");

        totalAmountOut = batchSwapExactInCore(
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

    function batchSwapExactInCore(
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
                if(k>0)
                    // Makes sure that from the second swap on, all the previous output was used 
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

    function batchSwapExactOut(
        Swap[][] memory swapSequences,
        address tokenIn,
        address tokenOut,
        uint maxTotalAmountIn
    )
        public
        _logs_
        _lock_
        returns (uint totalAmountIn)
    {
        TokenInterface TI = TokenInterface(tokenIn);
        TokenInterface TO = TokenInterface(tokenOut);
        require(TI.transferFrom(msg.sender, address(this), maxTotalAmountIn), "ERR_TRANSFER_FAILED");
        totalAmountIn = batchSwapExactOutCore(
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

    function batchSwapExactOutCore(
        Swap[][] memory swapSequences
    )
        internal
        returns (uint totalAmountIn)
    {
        for (uint i = 0; i < swapSequences.length; i++) {
            uint tokenAmountInFirstSwap;
            uint tokenAmountOutFirstSwap;
            for (uint k = 0; k < swapSequences[i].length; k++) {
                Swap memory swap = swapSequences[i][k];
                TokenInterface SwapTokenIn = TokenInterface(swap.tokenIn);

                PoolInterface pool = PoolInterface(swap.pool);
                if (SwapTokenIn.allowance(address(this), swap.pool) < uint(-1)) { // We don't know in advace how much tokenIn will be needed
                    SwapTokenIn.approve(swap.pool, uint(-1));
                }

                (uint tokenAmountIn,) = pool.swapExactAmountOut(
                                        swap.tokenIn,
                                        swap.limitReturnAmount,
                                        swap.tokenOut,
                                        swap.swapAmount,
                                        swap.maxPrice
                                    );

                // Store necessary info from first swap
                if(k==0){
                    tokenAmountInFirstSwap = tokenAmountIn; 
                    tokenAmountOutFirstSwap = swap.swapAmount;                 
                } 

                // If this is the second swap, check that tokenAmountIn == tokenAmountOutFirstSwap, if not
                // then tokenAmountIn must be lower than tokenAmountOutFirstSwap otherwise the second swap
                // would have reverted. Then we have to send the difference back to the user
                if(k==1){
                    if(tokenAmountOutFirstSwap>tokenAmountIn)
                        require(SwapTokenIn.transfer(msg.sender, tokenAmountOutFirstSwap-tokenAmountIn), "ERR_TRANSFER_FAILED");
                }
            }
            // This takes the amountIn of the first swap 
            totalAmountIn = add(tokenAmountInFirstSwap, totalAmountIn);
        }
        return totalAmountIn;
    }

    function batchEthInSwapExactIn(
        Swap[][] memory swapSequences,
        address tokenOut,
        uint minTotalAmountOut
    )
        public payable
        _logs_
        _lock_
        returns (uint totalAmountOut)
    {
        TokenInterface TO = TokenInterface(tokenOut);
        weth.deposit.value(msg.value)();

        totalAmountOut = batchSwapExactInCore(
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

    function batchEthOutSwapExactIn(
        Swap[][] memory swapSequences,
        address tokenIn,
        uint totalAmountIn,
        uint minTotalAmountOut
    )
        public
        _logs_
        _lock_
        returns (uint totalAmountOut)
    {
        TokenInterface TI = TokenInterface(tokenIn);
        require(TI.transferFrom(msg.sender, address(this), totalAmountIn), "ERR_TRANSFER_FAILED");
        
        // TODO: should we pass TI and TO to avoid loading costs in batchSwapExactInCore again?
        totalAmountOut = batchSwapExactInCore(
            swapSequences
        );

        require(totalAmountOut >= minTotalAmountOut, "ERR_LIMIT_OUT");
        uint wethBalance = weth.balanceOf(address(this));
        weth.withdraw(wethBalance);
        (bool xfer,) = msg.sender.call.value(wethBalance)("");
        require(xfer, "ERR_ETH_FAILED");

        uint TIBalance = TI.balanceOf(address(this));
        if(TIBalance>0)
            require(TI.transfer(msg.sender, TIBalance), "ERR_TRANSFER_FAILED");

        return totalAmountOut;
    }

    function batchEthInSwapExactOut(
        Swap[][] memory swapSequences,
        address tokenOut
    )
        public payable
        _logs_
        _lock_
        returns (uint totalAmountIn)
    {
        TokenInterface TO = TokenInterface(tokenOut);
        weth.deposit.value(msg.value)();

        totalAmountIn = batchSwapExactOutCore(
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

    function batchEthOutSwapExactOut(
        Swap[][] memory swapSequences,
        address tokenIn,
        uint maxTotalAmountIn
    )
        public
        _logs_
        _lock_
        returns (uint totalAmountIn)
    {
        TokenInterface TI = TokenInterface(tokenIn);
        require(TI.transferFrom(msg.sender, address(this), maxTotalAmountIn), "ERR_TRANSFER_FAILED");
        totalAmountIn = batchSwapExactOutCore(
            swapSequences
        );
        require(totalAmountIn <= maxTotalAmountIn, "ERR_LIMIT_IN");

        uint TIBalance = TI.balanceOf(address(this));
        if(TIBalance>0)
            require(TI.transfer(msg.sender, TIBalance), "ERR_TRANSFER_FAILED");
            
        uint wethBalance = weth.balanceOf(address(this));
        weth.withdraw(wethBalance);
        (bool xfer,) = msg.sender.call.value(wethBalance)("");
        require(xfer, "ERR_ETH_FAILED");
        return totalAmountIn;
    }

    function() external payable {}
}