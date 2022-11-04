// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "../../interfaces/IERC20.sol";
import "../../libraries/SafeMath.sol";
import "../../libraries/SafeERC20.sol";
import "../common/Op.sol";
import "../../interfaces/ILuckyPool.sol";
import "../../libraries/Address.sol";
import "../../libraries/EnumerableSet.sol";
import "../../types/ReentrancyGuard.sol";
import "../../interfaces/INFTPool.sol";
import "../../interfaces/IFactory.sol";
import "../../interfaces/IRewardPool.sol";

contract BSBall is Op, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;


    int256 constant fix = 25;
    int256 constant uFix = -25;
    uint256 constant maxNum = 5;
    uint256 constant muti = 100;
    uint256 public constant gameType = 3;

    IFactory public factory;
    IRewardPool public rewardPool;

    mapping(uint256 => mapping(uint256 => ConcedeInfo)) concedeInfo;
    mapping(uint256 => mapping(uint256 => mapping(uint256 => IndexInfo))) aIndexInfo;
    mapping(uint256 => mapping(uint256 => mapping(uint256 => IndexInfo))) bIndexInfo;
    mapping(uint256 => mapping(uint256 => mapping(uint256 => uint256))) public indexMaxTake;
    mapping(uint256 => mapping(uint256 => mapping(uint256 => bool))) public isAWinAll;
    mapping(uint256 => mapping(uint256 => mapping(uint256 => bool))) public isBWinAll;
    mapping(uint256 => mapping(uint256 => Result)) aResult;
    mapping(uint256 => mapping(uint256 => Result)) bResult;
    mapping(uint256 => mapping(uint256 => uint256)) public betValue;

    struct IndexInfo {
        uint256 betAmount;
        uint256 betValue;
        uint256 takeAmount;
    }

    struct ConcedeInfo {
        int256[] number;
        uint256[] payRate;
        uint256 totalBetAAmount;
        uint256 totalBetAValue;
        uint256 totalBetBAmount;
        uint256 totalBetBValue;
        uint256 maxTake;
        bool isBet;
        bool isSetRate;
        bool isOpen;
    }

    struct Cache {
        uint256 amount;
        uint256 value;
        uint256 fee;
        uint256 beforeTake;
        uint256 afterTake;
        uint256 maxTake;
    }

    struct Result {
        uint256[] winAll;
        uint256 winHalf;
        uint256 winPlate;
        uint256 loseHalf;
        bool isWinHalf;
        bool isWinPlate;
        bool isLoseHalf;
    }

    constructor(
        address factory_
    ) {
        factory = IFactory(factory_);
        rewardPool = IRewardPool(factory.rewardPool());
    }

    function _checkAccount(address account) internal view {
        require(account == owner() || account == operator, "no auth");
    }


    modifier onlyFactory() {
        require(msg.sender == address(factory), "not factory");
        _;
    }

    function bet(
        uint256 cupID,
        uint256 mID,
        uint256 amount,
        uint256 index,
        int256 choice
    ) external returns(uint256, uint256) {
        Cache memory cache = _checkBet(msg.sender, cupID, mID, amount, index, choice);
        uint256 before = concedeInfo[cupID][mID].maxTake;
        uint256 rate = _addAmount(cupID, mID, index, choice, cache);
        betValue[cupID][mID] = betValue[cupID][mID].add(cache.value);

        rewardPool.updateAmount(cache.value, before, concedeInfo[cupID][mID].maxTake, cache.fee);

        return (cache.value, rate);
    }

    function checkBet(
        uint256 cupID,
        uint256 mID,
        uint256 amount,
        uint256 index,
        int256 choice
    ) public view returns(bool) {
        _checkBet(msg.sender, cupID, mID, amount, index, choice);
        return true;
    }

    function _checkBet(
        address account,
        uint256 cupID,
        uint256 mID,
        uint256 amount,
        uint256 index,
        int256 choice
    ) internal view returns(Cache memory cache) {
        require(account == address(factory), "not factory");
        factory.checkGame(address(this), cupID, mID);
        require(concedeInfo[cupID][mID].isSetRate, "not set rate");
        require(concedeInfo[cupID][mID].isOpen, "BSBall not open");
        require(index < concedeInfo[cupID][mID].number.length, "index err");
        require(choice == 1 || choice == 2, "choice err");
        require(concedeInfo[cupID][mID].isSetRate, "not set rate");
        
        cache.fee = amount.mul(factory.feeRate()).div(baseRate);
        cache.value = amount - cache.fee;


        cache.beforeTake = indexMaxTake[cupID][mID][index];
        if(choice == 1 ) {
            cache.afterTake = cache.value.mul(concedeInfo[cupID][mID].payRate[index]).div(baseRate).add(aIndexInfo[cupID][mID][index].takeAmount);
        } else {
            cache.afterTake = cache.value.mul(concedeInfo[cupID][mID].payRate[index]).div(baseRate).add(bIndexInfo[cupID][mID][index].takeAmount);
        }


        if(cache.beforeTake < cache.afterTake) {
            cache.maxTake = cache.afterTake;
        } else {
            cache.maxTake = cache.beforeTake;
        }
        uint256 _bet = betValue[cupID][mID].add(cache.value);
        if(cache.maxTake < _bet) {
            cache.maxTake = _bet;
        } 

        cache.amount = amount;
        (uint256 total, uint256 poolTake) = rewardPool.getPoolAmount();
        require(poolTake.add(cache.maxTake) <= total.add(cache.beforeTake).add(cache.value), "BSBall out take");

    }


    function setNumber(        
        uint256 cupID,
        uint256 mID,
        int256[] memory number,
        uint256[] memory payRate
    ) 
        external  
    {
        checkSetBall(msg.sender, cupID, mID, number, payRate);
        concedeInfo[cupID][mID].number = number;
        concedeInfo[cupID][mID].payRate = payRate;

        if(!concedeInfo[cupID][mID].isSetRate) {
            concedeInfo[cupID][mID].isSetRate = true;
            concedeInfo[cupID][mID].isOpen = true;
        }
    }

    function setIsOpen(uint256 cupID, uint256 mID, bool isOpen) external {
        checkOpen(msg.sender, cupID, mID);
        concedeInfo[cupID][mID].isOpen = isOpen;
    }

    function checkOpen(address account, uint256 cupID, uint256 mID) public view returns(bool) {
        _checkAccount(account);
        factory.checkGame(address(this), cupID, mID);
        return true;
    }

    function checkSetBall(
        address account, 
        uint256 cupID,
        uint256 mID,
        int256[] memory number,
        uint256[] memory payRate
    ) public view returns(bool) {
        _checkAccount(account);
        require(_checkBall(cupID, mID, number, payRate), "set err");

        return true;
    }

    function _checkBall(
        uint256 cupID, 
        uint256 mID,
        int256[] memory num,
        uint256[] memory payRate
    ) internal view returns(bool) {
        require(!concedeInfo[cupID][mID].isBet, "can not set");
        uint256 uRate = factory.checkGame(address(this), cupID, mID);
        uint256 len = num.length;
        require(payRate.length == len, "not same");
        require(len > 0 && len <= maxNum, "length err");
        for(uint256 i = 0; i < len; i++) {
            uint256 _num = uint256(num[i]);
            if(_num.mod(25) != 0) {
                return false;
            } 

            if(i != len - 1) {
                if(num[i] >= num[i+1]) {
                    return false;
                }
            }

            if(payRate[i] <= baseRate || payRate[i] > uRate) {
                return false;
            }
            if(_num <= 0) {
                return false;
            }
        }

        return true;
    }

    function _addAmount( 
        uint256 cupID, 
        uint256 mID, 
        uint256 index,
        int256 choice, 
        Cache memory cache
    ) internal returns(uint256 rate) {
        if(choice == 1) {
            concedeInfo[cupID][mID].totalBetAAmount = concedeInfo[cupID][mID].totalBetAAmount.add(cache.amount);
            concedeInfo[cupID][mID].totalBetAValue = concedeInfo[cupID][mID].totalBetAValue.add(cache.value);
            aIndexInfo[cupID][mID][index].betAmount = aIndexInfo[cupID][mID][index].betAmount.add(cache.amount);
            aIndexInfo[cupID][mID][index].betValue = aIndexInfo[cupID][mID][index].betValue.add(cache.value);
            aIndexInfo[cupID][mID][index].takeAmount = cache.afterTake;
        
        } else {
            concedeInfo[cupID][mID].totalBetBAmount = concedeInfo[cupID][mID].totalBetBAmount.add(cache.amount);
            concedeInfo[cupID][mID].totalBetBValue = concedeInfo[cupID][mID].totalBetBValue.add(cache.value);
            bIndexInfo[cupID][mID][index].betAmount = bIndexInfo[cupID][mID][index].betAmount.add(cache.amount);
            bIndexInfo[cupID][mID][index].betValue = bIndexInfo[cupID][mID][index].betValue.add(cache.value);
            bIndexInfo[cupID][mID][index].takeAmount = cache.afterTake;
           
        }

        rate = concedeInfo[cupID][mID].payRate[index];
        concedeInfo[cupID][mID].maxTake = cache.maxTake;
    }

    function caculateMatch(
        uint256 cupID,
        uint256 mID
    ) external onlyFactory {
        if(!factory.getCancle(cupID, mID)){
            (uint256 aBall, uint256 bBall) = factory.getResult(cupID, mID);
            int256 aScore = int256(aBall.mul(muti));
            int256 bScore = int256(bBall.mul(muti));

            uint256 take1 = upperCase(cupID, mID, aScore, bScore);
            uint256 take2 = lowerCase(cupID, mID, aScore, bScore);

            rewardPool.updateValue(concedeInfo[cupID][mID].maxTake, take1.add(take2));
        } else {
            rewardPool.updateValue(concedeInfo[cupID][mID].maxTake, concedeInfo[cupID][mID].totalBetAValue.add(concedeInfo[cupID][mID].totalBetBValue));
        }

    }

    function upperCase(
        uint256 cupID,
        uint256 mID,
        int256 aScore,
        int256 bScore
    ) internal returns(uint256 take) {
        int256 x = aScore + bScore;
        for(uint256 i = 0; i < concedeInfo[cupID][mID].number.length; i++) {
            int256 _ball = concedeInfo[cupID][mID].number[i];
            if(x - _ball > fix) {
                aResult[cupID][mID].winAll.push(i);
                take = aIndexInfo[cupID][mID][i].takeAmount.add(take);
                isAWinAll[cupID][mID][i] = true;
            } else if(x - _ball == fix) {
                aResult[cupID][mID].winHalf = i;
                aResult[cupID][mID].isWinHalf = true;
                take = aIndexInfo[cupID][mID][i].takeAmount.div(2).add(take);
            } else if(x == _ball) {
                aResult[cupID][mID].winPlate = i;
                aResult[cupID][mID].isWinPlate = true;
                take = aIndexInfo[cupID][mID][i].betValue.add(take);
            } else if(x - _ball == uFix) {
                aResult[cupID][mID].loseHalf = i;
                aResult[cupID][mID].isLoseHalf = true;
                take = aIndexInfo[cupID][mID][i].betValue.div(2).add(take);
            }
        }
    }

    function lowerCase(
        uint256 cupID,
        uint256 mID,
        int256 aScore,
        int256 bScore
    ) internal returns(uint256 take) {
        int256 y = bScore + aScore;
        for(uint256 i = 0; i < concedeInfo[cupID][mID].number.length; i++) {
            int256 _ball = concedeInfo[cupID][mID].number[i];
            if(_ball - y > fix) {
                bResult[cupID][mID].winAll.push(i);
                take = bIndexInfo[cupID][mID][i].takeAmount.add(take);
                isBWinAll[cupID][mID][i] = true;
            } else if(_ball - y == fix) {
                bResult[cupID][mID].winHalf = i;
                bResult[cupID][mID].isWinHalf = true;
                take = bIndexInfo[cupID][mID][i].takeAmount.div(2).add(take);
            } else if(y == _ball) {
                bResult[cupID][mID].winPlate = i;
                bResult[cupID][mID].isWinPlate = true;
                take = bIndexInfo[cupID][mID][i].betValue.add(take);
            } else if(_ball - y == uFix) {
                bResult[cupID][mID].loseHalf = i;
                bResult[cupID][mID].isLoseHalf = true;
                take = bIndexInfo[cupID][mID][i].betValue.div(2).add(take);
            }
        }
    }


    function getClaim(
        uint256 cupID, 
        uint256 mID, 
        uint256 totalID
    ) external view returns(uint256) {
        require(msg.sender == address(factory), "not factory");
        if(!factory.getCancle(cupID, mID)) {
            (,,, uint256 amount) = getResult(cupID, mID, totalID);
            return amount;
        } else {
            (, , uint256 value) = factory.getChoiceRate(cupID, totalID);
            return value;
        }
    }

    function checkClaim(
        uint256 cupID, 
        uint256 mID, 
        uint256 totalID
    ) public view returns(uint256) {
        (,address betAddr) = factory.getGType(cupID, totalID);
        require(betAddr == address(this), "not bet this BSBall");
        if(!factory.getCancle(cupID, mID)) {
            (,,, uint256 amount) = getResult(cupID, mID, totalID);
            require(amount > 0, "not win Concede");

            return amount;
        } else {
            (, , uint256 value) = factory.getChoiceRate(cupID, totalID);
            return value;
        }
    }

    function getResult(
        uint256 cupID, 
        uint256 mID, 
        uint256 totalID
    ) public view returns(int256 ce, uint256 index, uint256 cType, uint256 amount) {
        (int256 choice, uint256 rate, uint256 value) = factory.getChoiceRate(cupID, totalID);
        index = factory.getIndex(cupID, totalID);
        ce = choice; 
        {
            if(isAWinAll[cupID][mID][index] || isBWinAll[cupID][mID][index]) {
                amount = value.mul(rate).div(baseRate);
                cType = 1;
            }
            if(
                (aResult[cupID][mID].winHalf == index && aResult[cupID][mID].isWinHalf) ||
                (bResult[cupID][mID].winHalf == index && bResult[cupID][mID].isWinHalf)
            ) {
                amount = amount = value.mul(rate).div(baseRate).div(2);
                cType = 2;
            }

            if(
                (aResult[cupID][mID].winPlate == index && aResult[cupID][mID].isWinPlate) ||
                (bResult[cupID][mID].winPlate == index && bResult[cupID][mID].isWinPlate)
            ) {
                amount = value;
                cType = 3;
            }
            if(
                (aResult[cupID][mID].loseHalf == index && aResult[cupID][mID].isLoseHalf) ||
                (bResult[cupID][mID].loseHalf == index && bResult[cupID][mID].isLoseHalf)
            ) {
                amount = value.div(2);
                cType = 4;
            }
        }       
    }

    function getAIndexInfo(uint256 cupID, uint256 mID, uint256 index) external view returns(IndexInfo memory) {
        return aIndexInfo[cupID][mID][index];
    } 

    function getBIndexInfo(uint256 cupID, uint256 mID, uint256 index) external view returns(IndexInfo memory) {
        return bIndexInfo[cupID][mID][index];
    } 

    function getAResult(uint256 cupID, uint256 mID) external view returns(Result memory) {
        return aResult[cupID][mID];
    }
    
    function getBResult(uint256 cupID, uint256 mID) external view returns(Result memory) {
        return bResult[cupID][mID];
    }

    function getConcedeInfo(uint256 cupID, uint256 mID) external view returns(ConcedeInfo memory) {
        return concedeInfo[cupID][mID];
    }
}