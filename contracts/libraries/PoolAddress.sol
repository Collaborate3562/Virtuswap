// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @title Provides functions for deriving a pool address from the factory, tokens, and the fee
library PoolAddress {
    bytes32 internal constant POOL_INIT_CODE_HASH =
        0x8c2a44b85e33b5df1586d7ad85c38b0ff312cabd519dc5d3be0f0fbd8c48d13f;

    function getSalt(address token0, address token1)
        internal
        pure
        returns (bytes32 salt)
    {
        salt = keccak256(abi.encode(token0, token1));
    }

    function computeAddress(
        address factory,
        address token0,
        address token1
    ) internal pure returns (address pool) {
        require(token0 < token1);

        bytes32 _salt = getSalt(token0, token1);

        pool = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            factory,
                            _salt,
                            POOL_INIT_CODE_HASH
                        )
                    )
                )
            )
        );
    }
}