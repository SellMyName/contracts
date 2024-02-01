// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/interfaces/external/IWETH9.sol";

contract SellMyName {
    event Dex(
        address factoryV3,
        address managerV3,
        address routerV2,
        string info
    );

    event Token(
        address indexed owner,
        address indexed token,
        address indexed pair,
        uint256 initialBalance,
        uint256 deploymentBlock,
        uint256 saleDurationBlocks,
        uint256 initialRate,
        uint256 ratePerBlock,
        string info
    );

    event Sale(
        address indexed buyer,
        uint256 ethAmount,
        uint256 tokenAmount
    );

    event Liquidity(
        address indexed pair,
        uint256 ethAmount,
        uint256 tokenAmount
    );

    struct TokenInfo {
        address owner;              // Owner of the token sale
        uint256 initialBalance;     // Initial balance of this token for sale
        uint256 ethBalance;         // ETH balance from token's sales
        uint256 sold;               // Amount of tokens sold
        uint256 deploymentBlock;    // Deployment block (start sale)
        uint256 saleDurationBlocks; // Duration of the sale in blocks
        uint256 initialRate;        // Initial token exchange rate (1 token = Wei)
        uint256 ratePerBlock;       // Increase in token rate with each block (Wei)
        bool isLiquidityAdded;      // Turns true after adding liquidity
    }

    struct DexInfo {
        address factoryV3; // Creation of Uniswap V3 pools and control over the protocol fees
        address managerV3; // Wraps Uniswap V3 positions in the ERC721 non-fungible token interface
        address routerV2;  // Uniswap V2 swap router 2
    }

    address public constant DEV = address(0x0);

    uint256 public dexId;
    mapping(uint256 => DexInfo) private _dexs;

    mapping(address => TokenInfo) private _tokens;

    IWETH9 public immutable weth;

    constructor(address _weth) {
        weth = IWETH9(_weth);
    }

    function addDex(
        address _factoryV3,
        address _managerV3,
        address _routerV2,
        string _info
    ) public returns(uint256) {
        dexId += 1;
        Dex storage dex = dexs[dexId];

        require(
            _factoryV3 != address(0) || _routerV2 != address(0), 
            "DEX is not configured."
        );

        if (
            _factoryV3 != address(0) &&
            _managerV3 != address(0)
        ) {
            dex.factoryV3 = _factoryV3;
            dex.managerV3 = _managerV3;
        }

        if (
            _routerV2 != address(0)
        ) {
            dex.routerV2 = _routerV2;
        }

        dex.info = _info;

        return dexId;
    }

    function getDex(
        uint256 _dexId
    ) public returns(
        DexInfo memory
    ) {
        return dexs[_dexId];
    }

    function getToken(
        uint256 _tokenAddress
    ) public returns(
        TokenInfo memory
    ) {
        return tokens[_tokenAddress];
    }

    function initializeTokenSale(
        uint256 _dexId,
        bool _isV3, // Uniswap V3 - true
        address _tokenAddress,
        uint256 _initialRate,
        uint256 _ratePerBlock,
        uint256 _saleDurationBlocks,
        string memory _info
    ) public returns(
        TokenInfo memory
    ) {
        uint256 initialTokenBalance = IERC20(_tokenAddress).balanceOf(address(this));

        require(msg.sender != address(0), "Owner is not a zero address.");
        require(_tokenAddress != address(0), "Token Address is not a zero address.");
        require(tokenSales[_tokenAddress].owner == address(0), "Token is already added.");
        require(initialTokenBalance > 0, "Total Balance must be greater than zero.");
        require(_saleDurationBlocks > 0, "Sale Duration Blocks must be greater than zero.");
        require(_initialRate > 0, "Initial Rate must be greater than zero.");
        require(_ratePerBlock > 0, "Rate Per Block must be greater than zero.");

        uint256 fee = IERC20(_tokenAddress).balanceOf(address(DEV));
        if (fee < initialTokenBalance / 100) {
            IERC20(_tokenAddress).transfer(DEV, initialTokenBalance / 100 - fee);
            initialTokenBalance = IERC20(_tokenAddress).balanceOf(address(this));
        }

        Dex storage dex = dexs[_dexId];

        if (_isV3) {
            if (
                dex.factoryV3 != address(0) &&
                dex.managerV3 != address(0)
            ) {
                IUniswapV3Factory factoryV3 = IUniswapV3Factory(dex.factoryV3);
                INonfungiblePositionManager managerV3 = INonfungiblePositionManager(dex.managerV3);

                uint160 sqrtPriceX96 = uint160(sqrt(
                    (sale.saleDurationBlocks * sale.ratePerBlock) + sale.initialRate
                ) << 96);
                address token0 = _tokenAddress < address(weth) ? _tokenAddress : address(weth);
                address token1 = _tokenAddress < address(weth) ? address(weth) : _tokenAddress;
                uint24 fee = 3000;

                PoolAddress.PoolKey memory poolKey = PoolAddress.PoolKey({
                    token0: token0,
                    token1: token1,
                    fee: fee
                });

                address pair = PoolAddress.computeAddress(address(factoryV3), poolKey);

                // Check if the pool is already initialized
                if (IUniswapV3Pool(pair).liquidity() == 0) {
                    factoryV3.createPool(token0, token1, fee);
                    IUniswapV3Pool(pair).initialize(sqrtPriceX96);
                }
            } else {
                revert("DEX is not configured for V3.");
            }
        } else {
            if (
                dex.routerV2 != address(0)
            ) {
                IUniswapV2Router02 routerV2 = IUniswapV2Router02(dex.routerV2);
                address pair = IUniswapV2Factory(routerV2.factory())
                    .createPair(msg.sender, routerV2.WETH());
                if (pair == address(0)) {
                    revert("Pair is not a zero address.");
                }
            } else {
                revert("DEX is not configured for V2.");
            }
        }

        TokenInfo storage sale = tokens[_tokenAddress];
        sale.owner = msg.sender;
        sale.initialBalance = initialTokenBalance;
        sale.deploymentBlock = block.number;
        sale.saleDurationBlocks = _saleDurationBlocks;
        sale.initialRate = _initialRate;
        sale.ratePerBlock = _ratePerBlock;

        emit Token(
            sale.owner,
            _tokenAddress,
            pair,
            sale.initialBalance,
            sale.deploymentBlock,
            sale.saleDurationBlocks,
            sale.initialRate,
            sale.ratePerBlock,
            _info
        );

        return tokens[_tokenAddress];
    }

    // Function to add liquidity with ETH
    function addLiquidityETH(
        address token,
        uint24 fee,
        uint256 amountTokenDesired,
        uint256 amountETHDesired,
        int24 tickLower,
        int24 tickUpper
    ) external payable {
        require(msg.value == amountETHDesired, "Incorrect ETH amount");

        // Convert ETH to WETH
        weth.deposit{value: msg.value}();

        // Approve the position manager to spend WETH and the ERC20 token
        weth.approve(address(positionManager), msg.value);
        IERC20(token).approve(address(positionManager), amountTokenDesired);

        // Struct for minting a new position
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token < address(weth) ? token : address(weth),
            token1: token < address(weth) ? address(weth) : token,
            fee: fee,
            tickLower: TickMath.MIN_TICK,
            tickUpper: TickMath.MAX_TICK,
            amount0Desired: token < address(weth) ? amountTokenDesired : msg.value,
            amount1Desired: token < address(weth) ? msg.value : amountTokenDesired,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        // Mint a new liquidity position
        (,,,d) = positionManager.mint(params);
    }

    function addLiquidity(
        address _token
    ) public returns (
        address pair,
        uint256 amountToken,
        uint256 amountETH,
        uint256 liquidity
    ) {
        Data storage t = tokens[_token];
        uint256 endBlock = t.deploymentBlock + t.saleBlocks;

        require(!t.isLiquidityAdded, "Liquidity already added");
        require(
            block.number > endBlock || (
                t.tokensSupply > 0 &&
                t.tokensSupply <= t.tokensSent
            ),
            "Sale period has not ended yet"
        );

        if (block.number <= endBlock) {
            t.saleBlocks = (block.number - t.deploymentBlock) + 300; // Through 300 blocks (1 hour)
            t.tokensSupply = 0; // Prohibit changing the number of blocks more than once
        } else {
            t.isLiquidityAdded = true;

            uint256 ethAmount = t.ethReceived;
            uint256 tokenAmount = ethAmount / ((t.saleBlocks * t.blockRate) + t.initRate);

            IERC20(_token).approve(address(router), tokenAmount);

            pair = IUniswapV2Factory(router.factory()).getPair(address(_token), router.WETH());

            emit Liquidity(
                pair,
                ethAmount,
                tokenAmount
            );

            //slither-disable-next-line arbitrary-send-eth
            (amountToken, amountETH, liquidity) =  router.addLiquidityETH{value: ethAmount}(
                address(_token),
                tokenAmount,
                0, // slippage is unavoidable
                0, // slippage is unavoidable
                t.owner,
                block.timestamp
            );
        }
    }

    function getCurrentRate(
        TokenSaleInfo memory sale
    ) public view returns (
        uint256 rate
    ) {
        uint256 blocksPassed = block.number - sale.deploymentBlock;
        rate = (blocksPassed * sale.ratePerBlock) + sale.initialRate;
    }

    function calculateMaxSellableTokens(
        TokenSaleInfo storage sale
    ) internal view returns (
        uint256 maxSellable
    ) {
        uint256 currentRate = getCurrentRate(sale);
        uint256 tokensLeft = sale.initialBalance - sale.sold;

        /*
            Solving for max sellable tokens:
            (tokensLeft - max) * currentRate <= sale.ethBalance + max * currentRate
            Rearranging terms and solving for max:
            tokensLeft * currentRate - max * currentRate <= sale.ethBalance + max * currentRate
            tokensLeft * currentRate <= sale.ethBalance + 2 * max * currentRate
            (tokensLeft * currentRate - sale.ethBalance) / (2 * currentRate) = max
        */
        maxSellable = ((tokensLeft * currentRate) - sale.ethBalance) / (2 * currentRate);
    }

    // Function to accept ETH and issue tokens for a specific token
    function buyTokens(
        address _tokenAddress
    ) public payable {
        require(
            msg.value > 0,
            "Must send ETH to buy tokens"
        );

        TokenSaleInfo storage sale = tokenSales[_tokenAddress];

        // Check if the sale is still ongoing
        require(
            block.number <= sale.deploymentBlock + sale.saleDurationBlocks,
            "Token sale period has ended"
        );
        // Check if the liquidity is added
        require(
            !sale.isLiquidityAdded,
            "Liquidity already added"
        );

        // Calculate the maximum number of tokens that can be sold while maintaining liquidity
        uint256 maxSellableTokens = calculateMaxSellableTokens(sale);
        uint256 maxTokensBasedOnETH = msg.value / getCurrentRate(sale);
        uint256 tokensToIssue = (maxTokensBasedOnETH > maxSellableTokens)
            ? maxSellableTokens
            : maxTokensBasedOnETH;

        // Calculate the ETH value for the tokens to be issued
        uint256 ethForTokens = tokensToIssue * getCurrentRate(sale);

        // Update the number of tokens sold
        sale.sold += tokensToIssue;

        // Transfer the tokens to the buyer
        require(
            IERC20(_tokenAddress).transfer(msg.sender, tokensToIssue),
            "Token transfer failed"
        );

        // Update the ETH balance for this token
        sale.ethBalance += ethForTokens;

        // Refund excess ETH, if any
        uint256 excessETH = msg.value - ethForTokens;
        if (excessETH > 0) {
            payable(msg.sender).transfer(excessETH);
        }

        emit Sale(msg.sender, ethForTokens, tokensToIssue);
    }

    function sqrt(uint256 x) internal pure returns (uint256) {
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }
}