// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../interfaces/IUniswapV2Pair.sol";
import "../../interfaces/IUniswapV2Router02.sol";
import "../../interfaces/IERC20.sol";
import "../../libraries/SafeMath.sol";
import "../../libraries/SafeERC20.sol";
// import "../../types/Ownable.sol";
import "../common/Operator.sol";
import "../../interfaces/IBonus.sol";

contract LetDaoSwap is Operator{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public immutable router;
    IERC20 public BET;
    IERC20 public LET;
    IBonus public bonusContract;

    constructor(
        address router_,
        address betToken,
        address letToken
    ) {
        require(router_ != address(0), "Router cannot be zero");
        router = router_;
        BET = IERC20(betToken);
        LET = IERC20(letToken);
    }

    struct DepositVars {
        address lpToken;
        address token0;
        address token1;
        uint256 amount0;
        uint256 amount1;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 prevToken0Bal;
        uint256 prevToken1Bal;
        uint256 deadline;
    }

    function setBonusContract(address account) external onlyOperator {
        bonusContract = IBonus(account);
    }

    function check(
        address lpToken_,
        address[] calldata path_,
        uint256 amount_
    ) public view returns(bool) {
        require(address(bonusContract) != address(0), "bonusContract err");
        require(amount_ > 0, "amount err");
        require(lpToken_ != address(0), "lpToken_ err");
        uint256 pathLength = path_.length;
        address token0 = IUniswapV2Pair(lpToken_).token0();
        address token1 = IUniswapV2Pair(lpToken_).token1();

        require(pathLength == 2 && path_[0] != path_[1], "path error");
        require(path_[0] == token0 || path_[0] == token1, "Token1 error");
        require(path_[1] == token0 || path_[1] == token1, "Token2 error");

        return true;
    }

    function depositSigleToken(
        address lpToken_,
        address[] calldata path_,
        uint256 amount_,
        uint256 amount0Min_,
        uint256 amount1Min_,
        uint256 deadline_
    ) external onlyContractAuth {
        check(lpToken_, path_, amount_);
        DepositVars memory vars;
        vars.amount0Min = amount0Min_;
        vars.amount1Min = amount1Min_;
        vars.deadline = deadline_;
        vars.lpToken = lpToken_;

        vars.token0 = IUniswapV2Pair(vars.lpToken).token0();
        vars.token1 = IUniswapV2Pair(vars.lpToken).token1();

        vars.prevToken0Bal = IERC20(vars.token0).balanceOf(address(this));
        vars.prevToken1Bal = IERC20(vars.token1).balanceOf(address(this));

        IERC20(path_[0]).safeTransferFrom(msg.sender, address(this), amount_);


        uint256 uAmount = amount_.div(4);
        uint256 amountSwap = amount_.sub(uAmount);
        IERC20(path_[0]).safeIncreaseAllowance(router, amountSwap);
        IUniswapV2Router02(router).swapExactTokensForTokens(amountSwap, 0, path_, address(this), vars.deadline);

        vars.amount0 = IERC20(vars.token0).balanceOf(address(this)).sub(vars.prevToken0Bal);
        vars.amount1 = IERC20(vars.token1).balanceOf(address(this)).sub(vars.prevToken1Bal);

        _depositLiquidity(vars);

        _refund(vars);
    }

    function _depositLiquidity(DepositVars memory vars_) internal {
        // add liquidity to the router
        IERC20(vars_.token0).safeIncreaseAllowance(router, vars_.amount0);
        IERC20(vars_.token1).safeIncreaseAllowance(router, vars_.amount1);

        (, , uint256 liquidity) =
            IUniswapV2Router02(router).addLiquidity(
                vars_.token0,
                vars_.token1,
                vars_.amount0,
                vars_.amount1,
                vars_.amount0Min,
                vars_.amount1Min,
                address(this),
                vars_.deadline
            );

        require(liquidity > 0, "Not enough liquidity");

        IERC20(vars_.lpToken).safeTransfer(msg.sender, liquidity);
    }

    function _refund(DepositVars memory vars_) internal {
        uint256 currToken0Bal = IERC20(vars_.token0).balanceOf(address(this));
        uint256 currToken1Bal = IERC20(vars_.token1).balanceOf(address(this));
        if (currToken0Bal > vars_.prevToken0Bal) {
            _transferFor(vars_.token0, currToken0Bal.sub(vars_.prevToken0Bal));
            //IERC20(vars_.token0).safeTransfer(msg.sender, currToken0Bal.sub(vars_.prevToken0Bal));
        }
        if (currToken1Bal > vars_.prevToken1Bal) {
            _transferFor(vars_.token1, currToken1Bal.sub(vars_.prevToken1Bal));
            //IERC20(vars_.token1).safeTransfer(msg.sender, currToken1Bal.sub(vars_.prevToken1Bal));
        }
    }

    function _transferFor(address token, uint256 amount) internal {
            if(token == address(BET)) {
                BET.burn(amount);
            } else if(token == address(LET)) {
                bonusContract.addBonusForm(msg.sender, amount);
                LET.safeTransfer(address(bonusContract), amount);
            } else {
                IERC20(token).safeTransfer(msg.sender, amount);
            }
    }

    function recoverLostToken(address token_) external onlyOwner() {
        IERC20(token_).safeTransfer(msg.sender, IERC20(token_).balanceOf(address(this)));
    }

}

