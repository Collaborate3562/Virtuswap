// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/lib/contracts/libraries/TransferHelper.sol";

import "./types.sol";
import "./vPair.sol";
import "./base/multicall.sol";
import "./libraries/PoolAddress.sol";
import "./libraries/vSwapLibrary.sol";
import "./interfaces/IvRouter.sol";
import "./interfaces/IvPairFactory.sol";
import "./interfaces/IvPair.sol";
import "./interfaces/external/IWETH9.sol";

contract vRouter is IvRouter, Multicall {
    address public override factory;
    address public immutable override WETH9;

    modifier _onlyFactoryAdmin() {
        require(msg.sender == IvPairFactory(factory).admin(), "VSWAP:ONLY_ADMIN");
        _;
    }

    modifier notAfter(uint256 deadline) {
        require(deadline >= block.timestamp, "VSWAP:EXPIRED");
        _;
    }

    constructor(address _factory, address _WETH9) {
        WETH9 = _WETH9;
        factory = _factory;
    }

    receive() external payable {
        require(msg.sender == WETH9, "Not WETH9");
    }

    function getPairAddress(address tokenA, address tokenB)
        internal
        view
        returns (address)
    {
        return PoolAddress.computeAddress(factory, tokenA, tokenB);
    }

    function getPair(address tokenA, address tokenB)
        internal
        view
        returns (IvPair)
    {
        return IvPair(getPairAddress(tokenA, tokenB));
    }

    function vFlashSwapCallback(
        address tokenIn,
        address tokenOut,
        uint256 requiredBackAmount,
        bytes calldata data
    ) external override {
        SwapCallbackData memory decodedData = abi.decode(
            data,
            (SwapCallbackData)
        );

        if (decodedData.jkPool > address(0)) {
            //validate JK pool
            (address jkToken0, address jkToken1) = IvPair(decodedData.jkPool)
                .getTokens();

            require(
                msg.sender ==
                    PoolAddress.computeAddress(factory, jkToken0, jkToken1),
                "VSWAP:INVALID_CALLBACK_VPOOL"
            );
        } else
            require(
                msg.sender ==
                    PoolAddress.computeAddress(factory, tokenIn, tokenOut),
                "VSWAP:INVALID_CALLBACK_POOL"
            );

        //validate amount to pay back dont exceeds
        require(
            requiredBackAmount <= decodedData.tokenInMax,
            "VSWAP:REQUIRED_AMOUNT_EXCEEDS"
        );
        // handle payment
        if (tokenIn == WETH9 && decodedData.ETHValue > 0) {
            require(
                decodedData.ETHValue >= requiredBackAmount,
                "VSWAP:INSUFFICIENT_ETH_INPUT_AMOUNT"
            );
            // pay back with WETH9
            IWETH9(WETH9).deposit{value: requiredBackAmount}();
            IWETH9(WETH9).transfer(msg.sender, requiredBackAmount);

            //send any ETH leftovers to caller
            payable(decodedData.caller).transfer(address(this).balance);
        } else {
            SafeERC20.safeTransferFrom(
                IERC20(tokenIn),
                decodedData.caller,
                msg.sender,
                requiredBackAmount
            );
        }
    }

    function unwrapTransferETH(address to, uint256 amount) internal {
        IWETH9(WETH9).withdraw(amount);
        payable(to).transfer(amount);
    }

    function swapExactOutput(
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 maxAmountIn,
        address to,
        uint256 deadline
    ) external payable override notAfter(deadline) {
        getPair(tokenIn, tokenOut).swapNative(
            amountOut,
            tokenOut,
            tokenOut == WETH9 ? address(this) : to,
            abi.encode(
                SwapCallbackData({
                    caller: msg.sender,
                    tokenInMax: maxAmountIn,
                    ETHValue: address(this).balance,
                    jkPool: address(0)
                })
            )
        );

        if (tokenOut == WETH9) {
            unwrapTransferETH(to, amountOut);
        }
    }

    function swapExactInput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address to,
        uint256 deadline
    ) external payable override notAfter(deadline) {
        uint256 amountOut = getAmountOut(tokenIn, tokenOut, amountIn);
        require(amountOut >= minAmountOut, "VSWAP: INSUFFICIENT_OUTPUT_AMOUNT");

        getPair(tokenIn, tokenOut).swapNative(
            amountOut,
            tokenOut,
            tokenOut == WETH9 ? address(this) : to,
            abi.encode(
                SwapCallbackData({
                    caller: msg.sender,
                    tokenInMax: amountIn,
                    ETHValue: address(this).balance,
                    jkPool: address(0)
                })
            )
        );

        if (tokenOut == WETH9) {
            unwrapTransferETH(to, amountOut);
        }
    }

    function swapReserveExactOutput(
        address tokenOut,
        address commonToken,
        address ikPair,
        uint256 amountOut,
        uint256 maxAmountIn,
        address to,
        uint256 deadline
    ) external payable override notAfter(deadline) {
        address jkAddress = getPairAddress(tokenOut, commonToken);

        IvPair(jkAddress).swapReserveToNative(
            amountOut,
            ikPair,
            tokenOut == WETH9 ? address(this) : to,
            abi.encode(
                SwapCallbackData({
                    caller: msg.sender,
                    tokenInMax: maxAmountIn,
                    ETHValue: address(this).balance,
                    jkPool: jkAddress
                })
            )
        );

        if (tokenOut == WETH9) {
            unwrapTransferETH(to, amountOut);
        }
    }

    function swapReserveExactInput(
        address tokenOut,
        address commonToken,
        address ikPair,
        uint256 amountIn,
        uint256 minAmountOut,
        address to,
        uint256 deadline
    ) external payable override notAfter(deadline) {
        address jkAddress = getPairAddress(tokenOut, commonToken);
        uint256 amountOut = getVirtualAmountOut(jkAddress, ikPair, amountIn);

        require(
            amountOut >= minAmountOut,
            "VSWAP: INSUFFICIENT_VOUTPUT_AMOUNT"
        );

        IvPair(jkAddress).swapReserveToNative(
            amountOut,
            ikPair,
            tokenOut == WETH9 ? address(this) : to,
            abi.encode(
                SwapCallbackData({
                    caller: msg.sender,
                    tokenInMax: amountIn,
                    ETHValue: address(this).balance,
                    jkPool: jkAddress
                })
            )
        );

        if (tokenOut == WETH9) {
            unwrapTransferETH(to, amountOut);
        }
    }

    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    )
        internal
        returns (
            uint256 amountA,
            uint256 amountB,
            address pairAddress
        )
    {
        pairAddress = IvPairFactory(factory).getPair(tokenA, tokenB);
        // create the pair if it doesn't exist yet
        if (pairAddress == address(0))
            pairAddress = IvPairFactory(factory).createPair(tokenA, tokenB);

        (uint256 reserve0, uint256 reserve1) = IvPair(pairAddress)
            .getBalances();

        if (reserve0 == 0 && reserve1 == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = vSwapLibrary.quote(
                amountADesired,
                reserve0,
                reserve1
            );

            if (amountBOptimal <= amountBDesired) {
                require(
                    amountBOptimal >= amountBMin,
                    "VSWAP: INSUFFICIENT_B_AMOUNT"
                );
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = vSwapLibrary.quote(
                    amountBDesired,
                    reserve1,
                    reserve0
                );

                assert(amountAOptimal <= amountADesired);
                require(
                    amountAOptimal >= amountAMin,
                    "VSWAP: INSUFFICIENT_A_AMOUNT"
                );
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        override
        notAfter(deadline)
        returns (
            uint256 amountA,
            uint256 amountB,
            address pairAddress,
            uint256 liquidity
        )
    {
        (amountA, amountB, pairAddress) = _addLiquidity(
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin
        );

        SafeERC20.safeTransferFrom(
            IERC20(tokenA),
            msg.sender,
            pairAddress,
            amountA
        );
        SafeERC20.safeTransferFrom(
            IERC20(tokenB),
            msg.sender,
            pairAddress,
            amountB
        );

        liquidity = IvPair(pairAddress).mint(to);
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        override
        notAfter(deadline)
        returns (uint256 amountA, uint256 amountB)
    {
        address pairAddress = getPairAddress(tokenA, tokenB);

        SafeERC20.safeTransferFrom(
            IERC20(pairAddress),
            msg.sender,
            pairAddress,
            liquidity
        );

        (amountA, amountB) = IvPair(pairAddress).burn(to);

        require(amountA >= amountAMin, "VSWAP: INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "VSWAP: INSUFFICIENT_B_AMOUNT");
    }

    function getVirtualAmountIn(
        address jkPair,
        address ikPair,
        uint256 amountOut
    ) external view override returns (uint256 amountIn) {
        VirtualPoolModel memory vPool = getVirtualPool(jkPair, ikPair);

        amountIn = vSwapLibrary.getAmountIn(
            amountOut,
            vPool.balance0,
            vPool.balance1,
            vPool.fee
        );
    }

    function getVirtualAmountOut(
        address jkPair,
        address ikPair,
        uint256 amountIn
    ) public view override returns (uint256 amountOut) {
        VirtualPoolModel memory vPool = getVirtualPool(jkPair, ikPair);

        amountOut = vSwapLibrary.getAmountOut(
            amountIn,
            vPool.balance0,
            vPool.balance1,
            vPool.fee
        );
    }

    function getVirtualPool(address jkPair, address ikPair)
        public
        view
        override
        returns (VirtualPoolModel memory vPool)
    {
        vPool = vSwapLibrary.getVirtualPool(jkPair, ikPair);
    }

    function quote(
        address inputToken,
        address outputToken,
        uint256 amountIn
    ) external view override returns (uint256 amountOut) {
        IvPair pair = getPair(inputToken, outputToken);

        (uint256 balance0, uint256 balance1) = pair.getBalances();

        (balance0, balance1) = vSwapLibrary.sortBalances(
            inputToken,
            pair.token0(),
            balance0,
            balance1
        );

        amountOut = vSwapLibrary.quote(amountIn, balance0, balance1);
    }

    function getAmountOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) public view virtual override returns (uint256 amountOut) {
        IvPair pair = getPair(tokenIn, tokenOut);

        (uint256 balance0, uint256 balance1) = pair.getBalances();

        (balance0, balance1) = vSwapLibrary.sortBalances(
            tokenIn,
            pair.token0(),
            balance0,
            balance1
        );

        amountOut = vSwapLibrary.getAmountOut(
            amountIn,
            balance0,
            balance1,
            pair.fee()
        );
    }

    function getAmountIn(
        address tokenIn,
        address tokenOut,
        uint256 amountOut
    ) external view virtual override returns (uint256 amountIn) {
        IvPair pair = getPair(tokenIn, tokenOut);
        (uint256 balance0, uint256 balance1) = IvPair(pair).getBalances();

        (balance0, balance1) = vSwapLibrary.sortBalances(
            tokenIn,
            pair.token0(),
            balance0,
            balance1
        );

        amountIn = vSwapLibrary.getAmountIn(
            amountOut,
            balance0,
            balance1,
            pair.fee()
        );
    }

    function changeFactory(address _factory)
        external
        override
        _onlyFactoryAdmin
    {
        require(
            _factory > address(0) && _factory != factory,
            "VSWAP:INVALID_FACTORY"
        );
        factory = _factory;

        emit RouterFactoryChanged(_factory);
    }
}
