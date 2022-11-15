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
import "../../interfaces/INFTPool.sol";
import "../../interfaces/IFactory.sol";
import "../../interfaces/IRewardPool.sol";

contract WinBall is Op {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;

    IFactory public factory;
    IRewardPool public rewardPool;
    uint256 public constant gameType = 1;


    mapping(uint256 => mapping(uint256 => TakeInfo)) public takeInfo;
    mapping(uint256 => mapping(uint256 => uint256)) public betValue;

    struct TakeInfo {
        uint256 aRate;
        uint256 bRate;
        uint256 pRate;
        uint256 aValue;
        uint256 bValue;
        uint256 pValue;
        uint256 aTake;
        uint256 bTake;
        uint256 pTake;
        uint256 maxTake;
        bool isSetRate;
        bool isOpen;
    }

    struct Cache {
        uint256 value;
        uint256 fee;
        uint256 beforeTake;
        uint256 afterTake;
        uint256 aTake;
        uint256 bTake; 
        uint256 pTake;
    }

    constructor(
        address factory_
    ) {
        factory = IFactory(factory_);
        rewardPool = IRewardPool(factory.rewardPool());
    }

    modifier onlyFactory() {
        require(msg.sender == address(factory), "not factory");
        _;
    }


    function setIsOpen(uint256 cupID, uint256 mID, bool isOpen) external {
        checkOpen(msg.sender, cupID, mID);
        takeInfo[cupID][mID].isOpen = isOpen;
    }

    function checkOpen(address account, uint256 cupID, uint256 mID) public view returns(bool) {
        _checkAccount(account);
        factory.checkGame(address(this), cupID, mID);
        return true;
    }

    function _checkAccount(address account) internal view {
        require(account == owner() || account == operator, "no auth");
    }

    function getClaim(
        uint256 cupID, 
        uint256 mID, 
        uint256 totalID
    ) external view returns(uint256) {
        require(msg.sender == address(factory), "not factory");
        if(!factory.getCancle(cupID, mID)) {
            (int256 choice, uint256 rate, uint256 value) = factory.getChoiceRate(cupID, totalID);
            if(uint256(factory.getWinType(cupID, mID)) == uint256(choice)) {
                return (rate.mul(value).div(baseRate));
            }
            return 0;
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
        require(betAddr == address(this), "not bet this WinBall");
        if(!factory.getCancle(cupID, mID)) {
            (int256 choice, uint256 rate, uint256 value) = factory.getChoiceRate(cupID, totalID);
            require(uint256(factory.getWinType(cupID, mID)) == uint256(choice), "not win");

            return (rate.mul(value).div(baseRate));
        } else {
            (, , uint256 value) = factory.getChoiceRate(cupID, totalID);
            return value;
        }
    }

    function setRate(
        uint256 cupID,
        uint256 mID,
        uint256 aRate,
        uint256 bRate,
        uint256 pRate
    ) external {
        checkRate(msg.sender, cupID, mID, aRate, bRate, pRate);
        takeInfo[cupID][mID].aRate = aRate;
        takeInfo[cupID][mID].bRate = bRate;
        takeInfo[cupID][mID].pRate = pRate;
        if(!takeInfo[cupID][mID].isSetRate) {
            takeInfo[cupID][mID].isSetRate = true;
            takeInfo[cupID][mID].isOpen = true;
        }

    }


    function checkRate(
        address account,
        uint256 cupID,
        uint256 mID,
        uint256 aRate,
        uint256 bRate,
        uint256 pRate
    ) public view returns(bool) {
        require(account == owner() || account == operator, "no auth");
        uint256 uRate = factory.checkGame(address(this), cupID, mID);
        require(
            aRate > baseRate &&
            aRate <= uRate &&
            bRate > baseRate &&
            bRate <= uRate &&
            pRate > baseRate &&
            pRate <= uRate,
            "rate err"
        );
        return true;
    }
    


    function bet(
        uint256 cupID,
        uint256 mID,
        uint256 amount,
        uint256 index,
        int256 choice
    ) external returns(uint256, uint256) {
        Cache memory cache = _checkBet(msg.sender, cupID, mID, amount, index, choice);

        betValue[cupID][mID] = betValue[cupID][mID].add(cache.value);
        uint256 rate = _addAmount(cupID, mID, choice, cache);
        rewardPool.updateAmount(cache.value, cache.beforeTake, cache.afterTake, cache.fee);

        return (cache.value, rate);
    }

    function checkBet(
        uint256 cupID,
        uint256 mID,
        uint256 amount,
        uint256 index,
        int256 choice
    ) external view returns(bool) {
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
    ) 
        public 
        view 
        returns(Cache memory cache) 
    {
        require(account == address(factory), "not factory");
        require(index == 0, "index err");
        factory.checkGame(address(this), cupID, mID);
        require(takeInfo[cupID][mID].isOpen, "WinBall not open");
        require(takeInfo[cupID][mID].isSetRate, "not set rate");
        require(choice > 0 && choice <= 3, "choice err");
        cache.fee = amount.mul(factory.feeRate()).div(baseRate);
        cache.value = amount - cache.fee;
        
        (
            cache.beforeTake,
            cache.afterTake,
            cache.aTake,
            cache.bTake,
            cache.pTake
        ) = getMaxTake(cupID, mID, choice, cache.value);

        (uint256 total, uint256 poolTake) = rewardPool.getPoolAmount();
        require(poolTake.add(cache.afterTake) <= total.add(cache.beforeTake).add(cache.value), "out take");
    }




// ************************************************************
    function getPayRate(
        uint256 cupID, 
        uint256 mID, 
        int256 choice
    ) external view returns(uint256 rate) {
        if(choice == 1) {
            rate = takeInfo[cupID][mID].aRate;
        }
        if(choice == 2) {
            rate = takeInfo[cupID][mID].bRate;
        }
        if(choice == 3) {
            rate = takeInfo[cupID][mID].pRate;
        }
    }


    function _addAmount( 
        uint256 cupID, 
        uint256 mID, 
        int256 cType, 
        Cache memory cache
    ) internal returns(uint256 rate) {
        TakeInfo storage tInfo = takeInfo[cupID][mID];
        if(cType == 1) {
            tInfo.aValue = tInfo.aValue.add(cache.value);
            tInfo.aTake = cache.aTake;
            rate = tInfo.aRate;
        }
        if(cType == 2) {
            tInfo.bValue = tInfo.bValue.add(cache.value);
            tInfo.bTake = cache.bTake;
            rate = tInfo.bRate;
        }
        if(cType == 3) {
            tInfo.pValue = tInfo.pValue.add(cache.value);
            tInfo.pTake = cache.pTake;
            rate = tInfo.pRate;
        }

        tInfo.maxTake = cache.afterTake;
    }

    function getMaxTake(
        uint256 cupID, 
        uint256 mID, 
        int256 cType, 
        uint256 amount
    ) public view returns(
        uint256 before, 
        uint256 maxTake,
        uint256 aTake,
        uint256 bTake,
        uint256 pTake
    ) {
        before = takeInfo[cupID][mID].maxTake;
        TakeInfo memory tInfo = takeInfo[cupID][mID];
        aTake = tInfo.aTake;
        bTake = tInfo.bTake;
        pTake = tInfo.pTake;

        if(cType == 1) {
            aTake = tInfo.aRate.mul(amount).div(baseRate).add(aTake);
        }
        if(cType == 2) {
            bTake = tInfo.bRate.mul(amount).div(baseRate).add(bTake);
        }
        if(cType == 3) {
            pTake = tInfo.pRate.mul(amount).div(baseRate).add(pTake);
        }

        uint256 _bet = betValue[cupID][mID].add(amount);

        maxTake = aTake;

        if(maxTake < _bet) {
            maxTake = _bet;
        }

        if(maxTake < bTake) {
            maxTake = bTake;
        }

        if(maxTake < pTake) {
            maxTake = pTake;
        }
    }

    function getTake(
        uint256 cupID, 
        uint256 mID, 
        int256 cType
    ) external view returns(uint256 max, uint256 cTake) {
        max = takeInfo[cupID][mID].maxTake;
        if(cType == 1) {
            cTake = takeInfo[cupID][mID].aTake;
        }
        if(cType == 2) {
            cTake = takeInfo[cupID][mID].bTake;
        }
        if(cType == 3) {
            cTake = takeInfo[cupID][mID].pTake;
        }
    }

    function caculateMatch(
        uint256 cupID,
        uint256 mID
    ) external onlyFactory {
        if(!factory.getCancle(cupID, mID)){
            uint256 wType = factory.getWinType(cupID, mID);
            uint256 take;
            if(wType == 1) {
                take = takeInfo[cupID][mID].aTake;
            }

            if(wType == 2) {
                take = takeInfo[cupID][mID].bTake;
            }

            if(wType == 3) {
                take = takeInfo[cupID][mID].pTake;
            }
            rewardPool.updateValue(takeInfo[cupID][mID].maxTake, take);
        } else {
            rewardPool.updateValue(
                takeInfo[cupID][mID].maxTake, 
                takeInfo[cupID][mID].aValue.add(takeInfo[cupID][mID].bValue).add(takeInfo[cupID][mID].pValue)
            );
        }
    }

}