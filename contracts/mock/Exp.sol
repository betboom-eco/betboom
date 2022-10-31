// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "../../libraries/SafeMath.sol";
import "../common/Op.sol";
import "../../libraries/EnumerableSet.sol";
import "../../interfaces/IERC20.sol";
import "../../libraries/SafeERC20.sol";
import "../../interfaces/INFTPool.sol";

contract Exp is Op {
    event TransferTo(address token, address account, uint256 amount);
    event GainExperience(
        address account,
        uint256 amount,
        uint256 tokenID,
        uint256 addExp,
        uint256 exp,
        uint8 round
    );

    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    INFTPool public nftPool;
    uint8 public levelID;
    uint256 public constant dayTime = 24 hours; 
    uint256 constant muti = 1e18;

    struct LevelInfo {
        uint256 levelExp;
        uint256 BETAmount;
        uint256 LETAmount;
        uint256 upTime;
    }

    struct MintInfo {
        uint256 perUnAmount;
        uint256 wareTime;
    }

    struct TokenIDExp {
        uint256 levelID;
        uint256 exp;
        uint256 upTime;
    }
    mapping(uint256 => TokenIDExp) public tokenIDExp;
    mapping(uint256 => mapping(uint256 => uint256)) public levelTime;
    mapping(uint256 => LevelInfo) public levelInfo;
    mapping(uint256 => MintInfo) public mintInfo;

    IERC20 public BET;
    IERC20 public LET;

    constructor(
        address bet_,
        address let_
    ) {
        BET = IERC20(bet_);
        LET = IERC20(let_); 

        initExp();
    }

    function initExp() internal {
        _setExp(levelID, 0, 0, 0, 0);
        _setMintInfo(levelID, 20e18/dayTime, 3 days);

        _setExp(++levelID, 50, 10e18, 0, 36 hours);
        _setMintInfo(levelID, 30e18/dayTime, 5 days);

        _setExp(++levelID, 100, 20e18, 0, 54 hours);
        _setMintInfo(levelID, 50e18/dayTime, 7 days);

        _setExp(++levelID, 200, 50e18, 0, 81 hours);
        _setMintInfo(levelID, 100e18/dayTime, 10 days);

        _setExp(++levelID, 500, 100e18, 0, 120 hours);
        _setMintInfo(levelID, 200e18/dayTime, 15 days);

        _setExp(++levelID, 2000, 400e18, 2e18, 180 hours);
        _setMintInfo(levelID, 400e18/dayTime, 20 days);

        _setExp(++levelID, 5000, 600e18, 5e18, 275 hours);
        _setMintInfo(levelID, 600e18/dayTime, 35 days);

        _setExp(++levelID, 20000, 1000e18, 10e18, 400 hours);
        _setMintInfo(levelID, 800e18/dayTime, 40 days);

        _setExp(++levelID, 80000, 2500e18, 25e18, 600 hours);
        _setMintInfo(levelID, 1000e18/dayTime, 50 days);

        _setExp(++levelID, 320000, 5000e18, 50e18, 1000 hours);
        _setMintInfo(levelID, 3000e18/dayTime, 60 hours);

        _setExp(++levelID, 1280000, 20000e18, 200e18, 1500 hours);
        _setMintInfo(levelID, 5000e18/dayTime, 60 days);

    }

    function setNFTPool(address account) external onlyOperator {
        nftPool = INFTPool(account);
    }

    function checkSetMint(
        uint256[] memory lid, 
        uint256[] memory perUn,
        uint256[] memory time
    ) public pure returns(bool) {
        require(getright(lid, perUn, time), "data err");

        return true;
    }

    function getright(        
        uint256[] memory lid, 
        uint256[] memory perUn,
        uint256[] memory time
    ) public pure returns(bool) {
        uint256 len = lid.length;
        require(
            len == perUn.length && len == time.length && len == 11, 
            "length err"
        );
        for(uint256 i = 0; i < 10; i++) {
            if(lid[i] >= lid[i+1] || perUn[i] >= perUn[i+1] || time[i] >= time[i+1]) {
                return false;
            }
        }
        return true;
    }


    function setMintInfos(
        uint256[] memory lid, 
        uint256[] memory perUn,
        uint256[] memory time
    ) external onlyOperator {
        checkSetMint(lid, perUn, time);
        for(uint256 i = 0; i < lid.length; i++) {
            _setMintInfo(lid[i], perUn[i], time[i]);
        }
    }

    function setMintInfo(
        uint256 lid, 
        uint256 perUn,
        uint256 time
    ) external onlyOperator {
        checkMint(lid, perUn, time);
        _setMintInfo(lid, perUn, time);
    } 

    function checkSetExp(
        uint8[] memory lid, 
        uint256[] memory exp, 
        uint256[] memory betAmount, 
        uint256[] memory letAmount,
        uint256[] memory time
    ) public pure returns(bool) {
        require(getExpRight(lid, exp, betAmount, letAmount, time), "data err");

        return true;
    }

    function getExpRight(
        uint8[] memory lid, 
        uint256[] memory exp, 
        uint256[] memory betAmount, 
        uint256[] memory letAmount,
        uint256[] memory time
    ) internal pure returns(bool) {
        uint256 len = lid.length;
        require(
            len == exp.length && 
            len == betAmount.length && 
            len == letAmount.length && 
            len == time.length && 
            len == 11, 
            "length err"
        );

        for(uint256 i = 0; i < 10; i++) {
            if(
                lid[i] > lid[i+1] || 
                exp[i]  > exp[i+1] || 
                betAmount[i]  > betAmount[i+1] || 
                letAmount[i]  > letAmount[i+1] || 
                time[i]  > time[i+1]
            ) {
                return false;
            }
        }
        return true;
    }


    function setExps(
        uint8[] memory lid, 
        uint256[] memory exp, 
        uint256[] memory betAmount, 
        uint256[] memory letAmount,
        uint256[] memory time
    ) external onlyOperator {
        checkSetExp(lid, exp, betAmount, letAmount, time);
        for(uint256 i = 0; i < lid.length; i++) {
            _setExp(lid[i], exp[i], betAmount[i], letAmount[i], time[i]);
        }
    }

    function setExp(
        uint8 lid, 
        uint256 exp, 
        uint256 betAmount, 
        uint256 letAmount,
        uint256 time
    ) external onlyOperator {
        checkExp(lid, exp, betAmount, letAmount, time);
        _setExp(lid, exp, betAmount, letAmount, time);
    }

   function upgrade(uint256 tokenID) external {
        checkUpdate(tokenID);
        nftPool.updatePool(tokenID);
        
        uint256 lid = ++tokenIDExp[tokenID].levelID;
        tokenIDExp[tokenID].exp = 0;
        tokenIDExp[tokenID].upTime = block.timestamp;
        uint256 bAmount = levelInfo[lid].BETAmount;
        uint256 lAmount = levelInfo[lid].LETAmount;
        if(bAmount > 0) {
            BET.safeTransferFrom(msg.sender, address(this), bAmount);
        }
        if(lAmount > 0) {
            LET.safeTransferFrom(msg.sender, address(this), lAmount);
        }
    }

    function transferTo(address token, address account, uint256 amount) public onlyOwner {
        require(IERC20(token).balanceOf(address(this)) >= amount, "not enough");
        require(account != address(0), "not zero address");
        IERC20(token).safeTransfer(account, amount);
        
        emit TransferTo(token, account, amount);
    }

    function checkMint(
        uint256 lid, 
        uint256 perUn, 
        uint256 time
    ) public view returns(bool) 
    {
        require(lid < 11, "level lid err");
        if(lid == 0) {
            require(perUn <= mintInfo[lid+1].perUnAmount, "perUnAmount err");
            require(time <= mintInfo[lid+1].wareTime, "time err" );
        } else if(lid != 10) {
            require(
                perUn >= mintInfo[lid-1].perUnAmount &&
                perUn <= mintInfo[lid+1].perUnAmount
                , "perUnAmount err");

            require(
                time >= mintInfo[lid-1].wareTime &&
                time <= mintInfo[lid+1].wareTime,
                "time err"
            );
        } else {
            require(perUn >= mintInfo[lid-1].perUnAmount, "perUnAmount err");
            require(time >= mintInfo[lid-1].wareTime, "time err" );
        }

        return true;
    }


    function _setMintInfo(uint256 lid, uint256 perUn, uint256 time) internal {
        mintInfo[lid].perUnAmount = perUn;
        mintInfo[lid].wareTime = time;
    }

    function _setExp(
        uint8 lid, 
        uint256 exp, 
        uint256 betAmount, 
        uint256 letAmount,
        uint256 time
    ) internal {
        levelInfo[lid].levelExp = exp;
        levelInfo[lid].BETAmount = betAmount;
        levelInfo[lid].LETAmount = letAmount;
        levelInfo[lid].upTime = time;
    }


    function checkExp(
        uint8 lid, 
        uint256 exp, 
        uint256 betAmount, 
        uint256 letAmount,
        uint256 time
    ) public view returns(bool) {
        require(lid > 0 && lid < 11, "level lid err");
        if(lid == 0) {
            require(exp == 0 && betAmount == 0 && letAmount == 0 && time == 0, "zero level not set data");
        } else if(lid != 10) {
            require(
                exp >= levelInfo[lid-1].levelExp &&
                exp <= levelInfo[lid+1].levelExp,
                "exp err"
            );
            require(
                betAmount >= levelInfo[lid-1].BETAmount &&
                betAmount <= levelInfo[lid+1].BETAmount,
                "betAmount err"
            );
            require(
                letAmount >= levelInfo[lid-1].LETAmount &&
                letAmount <= levelInfo[lid+1].LETAmount,
                "letAmount err"
            );
            require(
                time >= levelInfo[lid-1].upTime &&
                time <= levelInfo[lid+1].upTime,
                "time err"
            );

        } else {
            require(exp >= levelInfo[lid-1].levelExp, "exp err");
            require(betAmount >= levelInfo[lid-1].BETAmount, "betAmount err");
            require(letAmount >= levelInfo[lid-1].LETAmount, "letAmount err");
            require(time >= levelInfo[lid-1].upTime, "time err");
        }
        
        return true;
    }
    
    function gainExperience(
        uint256 amount,
        uint256 tokenID,
        uint8 round
    ) external  {
        require(msg.sender == address(nftPool), "not nftPool");
        uint256 level = tokenIDExp[tokenID].levelID;
        if(level < 10) {
            uint256 exp = getEX(round, amount);
            tokenIDExp[tokenID].exp = tokenIDExp[tokenID].exp.add(exp);
            if(tokenIDExp[tokenID].exp > levelInfo[level+1].levelExp) {
                tokenIDExp[tokenID].exp = levelInfo[level+1].levelExp;
            }
            
            if(tokenIDExp[tokenID].upTime == 0) {
                tokenIDExp[tokenID].upTime = block.timestamp;
            }

            emit GainExperience(msg.sender, amount, tokenID, exp, tokenIDExp[tokenID].exp, round);
        }

    }

    function getEX(uint8 round, uint256 amount) public pure returns(uint256) {
        amount = amount.mul(1e18).div(1e6);
        return amount.mul(uint256(round)).mul(uint256(round)).div(muti);
    }

    function checkUpdate(uint256 tokenID) public view returns(bool) {
        uint256 lid = tokenIDExp[tokenID].levelID;
        require(lid < 10, "not update");
        require(tokenIDExp[tokenID].exp >= levelInfo[lid+1].levelExp, "not enough exp");
        require(
            block.timestamp.sub(tokenIDExp[tokenID].upTime) >= 
            levelInfo[lid+1].upTime,
            "not upTime"
        );
        return true;
    }

    function getUpTime(uint256 tokenID) external view returns(uint256){
        uint256 lid = tokenIDExp[tokenID].levelID;
        uint256 time = tokenIDExp[tokenID].upTime.add(levelInfo[lid+1].upTime);
        if(block.timestamp < time) {
            return time.sub(block.timestamp);
        }
        return 0;
    }

    function getCap(uint256 lid) external view returns(uint256) {
        return mintInfo[lid].perUnAmount.mul(mintInfo[lid].wareTime);
    }
}