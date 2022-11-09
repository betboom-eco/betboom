// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

pragma experimental ABIEncoderV2;

import "../common/Op.sol";
import "../../types/ReentrancyGuard.sol";
import "../../libraries/SafeMath.sol";
import "../../interfaces/IERC20.sol";
import "../../libraries/SafeERC20.sol";
import "../../interfaces/IFactory.sol";
import "../common/RewardParama.sol";
import "../../libraries/EnumerableSet.sol";
import "../../interfaces/ILetDaoSwap.sol";
import "../../interfaces/ILetDao.sol";

contract RewardPool is ReentrancyGuard, RewardParama {
    event AddPoolAmount(address indexed account, uint256 tokenAmount, uint256 lpAmount, uint256 addTime);
    event ClaimInsurer(address indexed account, uint256 lpAmount, uint256 tokenAmount, uint256 time);
    event OnlyAddAmount(address owner, uint256 amount);
    event TransferTo(address token, address account, uint256 amount);
    event RewardPro(address pro, uint256 amount);
    event LuckyReward(address user, uint256 amount);
    event RewardDao(address dao, uint256 amount);
    
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 constant multi = 1e18;
    uint256 constant E6 = 1e6;
    uint256 public insurerID;
    uint256 public lockTime = 24 hours;
    uint256 public deployBlock;
    uint256 public cumulativeAdd;
    uint256 public nob;
    uint256 public weekDays = 7 days;
    uint256 public weekNum;
    uint256 public totalReward;

    uint256 public actCaculateLpAmount;
    uint256 public maxNum = 30;
    uint256 public coe = 1000;
    uint256 public totalBetAmount;
    uint256 public daoLetUserAmount;
    uint256 public letUserReward;
    uint256 public daoLuckyAmount;
    uint256 public swapLetAmount;
    uint256 public swapBetAmount;
    uint256 public totalBAmount;
    uint256 public rewardAmount = 10e18;
    uint256 nonce;
    bool public isRank;
    bool public initTime;

    address public proAccount;
    address public daoAccount;
    address public betUsdt;
    address public letUsdt;

    EnumerableSet.AddressSet betUser;
    IERC20 public rewardToken;
    IERC20 public lpToken;
    PoolInfo public poolInfo;
    IFactory public factory;
    EsnInfo public esnInfo;
    IERC20 public immutable LET;
    IERC20 public immutable BET;
    ILetDaoSwap public ldSwap;



    struct LuckeyUser {
        address user;
        uint256 amount;
    }

    struct UserMint {
        uint256 betAmount;
        uint256 letAmount;
    }

    struct BnbTime {
        uint256 startTime;
        uint256 actTime;
    }

    struct Decay {
        uint256 decay;
        uint256 base;
    }


    struct Week {
        uint256 startTime;
        uint256 endTime;
    }

    struct PoolInfo {
        uint256 totalAmount;
        uint256 earnAmount;
        uint256 loseAmount;
        uint256 maxTakeAmount;
    }

    struct EsnInfo {
        uint256 totalAmount;
        uint256 esnAmount;
        uint256 esnNum;
        uint256 rewardPerTokenStored;
        uint256 totalLPStake;
    }

    struct UserInfo {
        uint256 userRewardPerTokenPaid;
        uint256 rewards;
        uint256 haveRecive;
        uint256 balances;
    }
    
    mapping(address => UserInfo) public userInfo;
    mapping(address => uint256) public insurerAddressToID;
    mapping(uint256 => address) public insurerIDToAddress;
    mapping(address => uint256) public insurerLastTime;
    mapping(uint256 => Week) public week;
    mapping(uint256 => Decay) decay;
    mapping(uint256 => EnumerableSet.AddressSet) users;
    mapping(uint256 => LuckeyUser) public luckeyUser;
    mapping (uint256 => address) public bnbUser;
    mapping(uint256 => uint256) public totalWeekAmount;
    mapping(uint256 => mapping(address => uint256)) public totalWeekUserAmount;
    mapping(uint256 => EnumerableSet.AddressSet) weekUser;
    mapping(address => mapping(uint256 => UserMint)) public userMint;
    mapping(address => mapping(uint256 => UserMint)) public userWeekMint;
    mapping(uint256 => BnbTime) public bnbTime;
    mapping(uint256 => mapping(address => uint256)) userTotalBet;
    mapping(address => uint256) public userBet;
    mapping(uint256 => uint256) public nobReward;

    constructor(
        address _token, 
        address _let,
        address _bet,
        address proAddr
    )  {
        
        require(address(0) != proAddr, "not zero address");
        proAccount = proAddr;
        rewardToken = IERC20(_token);
        deployBlock = block.number;
        LET = IERC20(_let);
        BET = IERC20(_bet);
        nob = ++esnInfo.esnNum;
        
        week[weekNum].startTime = block.timestamp;
        setDecay();
    }
    
    modifier checkRate(uint256 _rate) {
        require(_rate <= baseRate, "_rate err");
        _;
    }

    modifier onlyFactory {
        require(msg.sender == address(factory), "not playGame");
        _;
    }

    modifier updateReward(address account) {
        if (account != address(0)) {
            userInfo[account].rewards = earned(account);
            userInfo[account].userRewardPerTokenPaid = esnInfo.rewardPerTokenStored;
        }
        _;
    }    
    
    modifier checkAmount(uint256 amount) {
        require(amount > 0, "not zero");
        _;
    }

    function setExplosionAmount(uint256 amount) external onlyOperator {
        require(amount > esnInfo.esnAmount, "amount err");
        explosionAmount = amount;
    }

    function setFactory(address factory_) external onlyOperator {
        factory = IFactory(factory_);
    }

    function onlyAddAmount(uint256 amount) external {
        require(amount > 0 && rewardToken.balanceOf(msg.sender) >= amount, "amount err");
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        poolInfo.totalAmount = poolInfo.totalAmount.add(amount);
        actCaculateLpAmount = actCaculateLpAmount.add(amount); 
        cumulativeAdd = cumulativeAdd.add(amount);

        emit OnlyAddAmount(msg.sender, amount);
    }

    function setLockTime(uint256 time_)  external onlyOperator {
        lockTime = time_;
    }

    function setLPToken(address _lpToken) external onlyOperator {
        lpToken = IERC20(_lpToken);
    }

    function addPoolAmount(uint256 tokenAmount) 
        external 
        nonReentrant
        checkAmount(tokenAmount) 
        updateReward(msg.sender)
    {
        update();
        uint256 _id = insurerAddressToID[msg.sender];
        if(_id == 0) {
            _id = ++insurerID;
            insurerAddressToID[msg.sender] = _id;
            insurerIDToAddress[_id] = msg.sender;    
        }
        
        insurerLastTime[msg.sender] = block.timestamp;
        stake(tokenAmount);
        poolInfo.totalAmount = poolInfo.totalAmount.add(tokenAmount);
        actCaculateLpAmount = actCaculateLpAmount.add(tokenAmount);
    }
    
    function claimInsurer(uint256 lpAmount) 
        external 
        nonReentrant
        checkAmount(lpAmount) 
        updateReward(msg.sender)
    {
        (uint256 _value, uint256 _lp) = checkClaim(msg.sender, lpAmount);
        update();
        withdraw(_value, _lp);       
    }

    event ClaimReward(address user, uint256 reward);
    function claimReward() external updateReward(msg.sender) {
        update();
        uint256 reward = userInfo[msg.sender].rewards;
        require(reward > 0, "no reward");
        userInfo[msg.sender].haveRecive = userInfo[msg.sender].haveRecive.add(reward);
        userInfo[msg.sender].rewards = 0;
        LET.safeTransfer(msg.sender, reward);

        emit ClaimReward(msg.sender, reward);
    }

    function totalSupplyAmount() public view returns (uint256) {
        return lpToken.totalSupply();
    }

    function getBalanceOf(address account) public view returns (uint256) {
        return lpToken.balanceOf(account);
    }

    function stake(uint256 amount) internal {
        uint256 _value = amount.mul(getLpToToken()).div(E6);
        lpToken.mint(address(this), _value);
        esnInfo.totalLPStake = esnInfo.totalLPStake.add(_value);
        userInfo[msg.sender].balances =  userInfo[msg.sender].balances.add(_value);

        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        emit AddPoolAmount(msg.sender, amount, _value, block.timestamp);
    }

    function withdraw(uint256 _value, uint256 amount) internal {
        poolInfo.totalAmount = poolInfo.totalAmount.sub(_value);
        actCaculateLpAmount = poolInfo.totalAmount;

        //lpToken.safeTransferFrom(msg.sender, address(this), amount);
        esnInfo.totalLPStake = esnInfo.totalLPStake.sub(amount);
        userInfo[msg.sender].balances =  userInfo[msg.sender].balances.sub(amount);
        lpToken.burn(amount);
 
        rewardToken.safeTransfer(msg.sender, _value);
        emit ClaimInsurer(msg.sender, amount, _value, block.timestamp); 
    }

    function getBalanceOf() public view returns (uint256, uint256) {
        return (getPoolTotalAmount(), lpToken.totalSupply());
    }

    function getLpToToken() public view returns(uint256) {
        if(totalSupplyAmount() == 0) {
            return E6;
        }
        return totalSupplyAmount().mul(E6).div(actCaculateLpAmount);
    }
    
    function getTokenToLp() public view returns(uint256) {
        if(actCaculateLpAmount == 0) {
            return 0;
        }
        return actCaculateLpAmount.mul(E6).div(totalSupplyAmount());
    }
    
    function getUseAmount() external view returns(uint256) {
        if(poolInfo.totalAmount > poolInfo.maxTakeAmount) {
            return poolInfo.totalAmount - poolInfo.maxTakeAmount;
        }
        return 0;
    }
    
    function getMaxTakeAmount() external view returns(uint256) {
        return poolInfo.maxTakeAmount;
    }
    
    function getPoolTotalAmount() public view returns(uint256) {
        return poolInfo.totalAmount;
    }


    function checkClaim(address user, uint256 amount) public view returns(uint256, uint256) {
        require(userInfo[user].balances >= amount, "amount too big");
        (uint256 lastTime, uint256 notCacuNum) = factory.getEndInfo();
        require(block.timestamp > lastTime.add(lockTime), "not in unLockTime");
        require(notCacuNum == 0, "some match not caculate");

        {
            uint256 tValue = poolInfo.maxTakeAmount;
            require(poolInfo.totalAmount >= tValue, "out range");

            uint256 _value = amount.mul(getTokenToLp()).div(E6);
            uint256 afterAmount = poolInfo.totalAmount.sub(_value);
     
            if(afterAmount >= tValue) {                
                return (_value, amount);
            } else {
                uint256 _v = poolInfo.totalAmount.sub(tValue);
                uint256 _amount = _v.mul(E6).div(getTokenToLp());

                return (_v, _amount);
            }
        }

    }


    function updateAmount(uint256 amount, uint256 beforeTake, uint256 afterTake, uint256 fee) 
        external  
    {
        require(factory.getInGame(msg.sender) || msg.sender == address(factory), "no auth");      
        if(amount > 0) {
            poolInfo.totalAmount = poolInfo.totalAmount.add(amount);
        }
            
        poolInfo.maxTakeAmount = poolInfo.maxTakeAmount.add(afterTake).sub(beforeTake);
        esnInfo.esnAmount = esnInfo.esnAmount.add(fee);
        esnInfo.totalAmount = esnInfo.totalAmount.add(fee);
        poolInfo.earnAmount = poolInfo.earnAmount.add(amount);
    }

    function updateCaculateAmount(uint256 amount) external {
        require(msg.sender == address(factory), "auth err");
        actCaculateLpAmount = actCaculateLpAmount.add(amount);
    }

    function updateValue(uint256 maxTake, uint256 take) external {
        require(factory.getInGame(msg.sender) || msg.sender == address(factory), "no auth");    
        update();
        poolInfo.maxTakeAmount = poolInfo.maxTakeAmount.sub(maxTake);
        poolInfo.totalAmount = poolInfo.totalAmount.sub(take);
        poolInfo.loseAmount = poolInfo.loseAmount.add(take);
        actCaculateLpAmount = actCaculateLpAmount.sub(take); 
    }

    function cliam(address user, uint256 amount) external  {
        require(msg.sender == address(factory), "not factory");
        rewardToken.safeTransfer(user, amount);
    }

    // ******************************************
    function setWeekDays(uint256 time) external onlyOperator {
        require(time > 0, "time err");
        weekDays = time;
    }


    function update() public {
        uint256 time = block.timestamp;
        if(week[weekNum].startTime.add(weekDays) <= time) {
            week[weekNum].endTime = time;
            week[++weekNum].startTime = time;
            setDecay();
        }
    }

    function getTokenAmount(
        uint256 amount, 
        uint256 rate, 
        uint256 divisor, 
        uint256 num
    ) external view returns(uint256 bAmount, uint256 lAmount) {
        amount = amount.mul(1e18).div(E6);

        uint256 num1 = 2;
        if(num > 1) {
            for(uint256 i = 1; i < num; i++) {
                num1 = num1 * 2;
            }
        }
        uint256 num2 = nob;
        if(num2 > maxNum) {
            num2 = maxNum;
        }

        uint256 n = amount.mul(rate).mul(num).mul(decay[weekNum].decay); 
        lAmount = n.div(divisor).div(coe).div(decay[weekNum].base).div(num1);
        if(num > 2) {
            num = num * (num-1);
        }

        uint256 b = amount.mul(rate).mul(num);
        bAmount = b.div(divisor).div(num2).div(num1);  
    }

    function setCoe(uint256 num) external onlyOperator {
        require(num > 0, "num err");
        coe = num;
    }

    function setMaxNum(uint256 num) external onlyOperator {
        require(num > 0, "num err");
        maxNum = num;
    }

    uint256 maxWeek = 4;
    function setDecay() internal {
        if(weekNum == 0) {
            decay[weekNum].decay = 1;
            decay[weekNum].base = 1;
        } else {
            if(weekNum <= maxWeek) {
                decay[weekNum].decay = decay[weekNum-1].decay.mul(85);
                decay[weekNum].base = decay[weekNum-1].base.mul(100); 
            }else  {
                decay[weekNum].decay = decay[maxWeek].decay;
                decay[weekNum].base = decay[maxWeek].base;
            }  
        }
    }

    function getDecay(uint256 wNum) external view returns(uint256, uint256) {
        require(wNum <= weekNum, "wNum err");

        return (decay[wNum].decay, decay[wNum].base);
    }

    function getPoolAmount() external view returns(uint256, uint256) {
        return (poolInfo.totalAmount, poolInfo.maxTakeAmount);
    }


    // **************************************




   function setRate(
        uint256 initRate_,
        uint256 betLpRate_,
        uint256 letLpRate_,
        uint256 letUserRate_,
        uint256 pragmaRate_,
        uint256 luckyRate_      
    ) 
        external 
        onlyOperator 
    {
        uint256 num =  initRate_.add(betLpRate_).add(letLpRate_);
        num = num.add(letUserRate_).add(pragmaRate_).add(luckyRate_);
        require(num == baseRate, "out range");

        initRate = initRate_;
        betLpRate = betLpRate_;
        letLpRate = letLpRate_;
        letUserRate = letUserRate_;
        pragmaRate = pragmaRate_;
        luckyRate = luckyRate_;
    }

    function setRank() external {
        require(msg.sender == daoAccount, "not dao contract");
        isRank = true;
    } 

    function setProAccount(address account) external onlyOperator {
        require(address(0) != account, "not zero address");

        proAccount = account;
    }

    function setDaoAccount(address account) external onlyOperator {
        daoAccount = account;
    }

    function setLP(address betUsdtLp, address letUsdtLp) external onlyOperator {
        betUsdt = betUsdtLp;
        letUsdt = letUsdtLp;
    }

    function setLetDaoSwap(address account) external onlyOperator {
        ldSwap = ILetDaoSwap(account);
    }

    function transferTo(address token, address account, uint256 amount) public onlyOwner {
        require(IERC20(token).balanceOf(address(this)) >= amount, "not enough");
        IERC20(token).safeTransfer(account, amount);
        
        emit TransferTo(token, account, amount);
    } 


    function addMint(address user, uint256 amount, uint256 bAmount, uint256 lAmount) external onlyFactory {
        update();
        users[nob].add(user);
        betUser.add(user);
        userBet[user] = userBet[user].add(amount);
        totalBetAmount = totalBetAmount.add(amount);
        userTotalBet[nob][user] = userTotalBet[nob][user].add(amount);
        userMint[user][nob].betAmount = userMint[user][nob].betAmount.add(bAmount);
        userMint[user][nob].letAmount = userMint[user][nob].letAmount.add(lAmount);

        if(isRank && address(0) != daoAccount) {
            uint256 wID = ILetDao(daoAccount).weekID();
            totalWeekAmount[wID] = totalWeekAmount[wID].add(amount);
            totalWeekUserAmount[wID][user] = totalWeekUserAmount[wID][user].add(amount);
            weekUser[wID].add(user);
            
            userWeekMint[user][wID].betAmount = userWeekMint[user][wID].betAmount.add(bAmount);
            userWeekMint[user][wID].letAmount = userWeekMint[user][wID].letAmount.add(lAmount);
        }
    }

    function setUpAmount(uint256 amount) external onlyOperator {
        require(amount >= poolInfo.totalAmount && amount > 0, "new up amount err");
        upAmount = amount;
    }

    function blast(address user) external onlyFactory {
        if(esnInfo.esnAmount >= explosionAmount) {
            explosionAmount = explosionAmount.add(addAmount);
            if(explosionAmount > upAmount) {
                explosionAmount = upAmount;
            }
            totalBAmount = totalBAmount.add(esnInfo.esnAmount);
            AllocateAssets();
            distReward();
            inDaoAmount();
            luckyReward();
            letSwap();
            betSwap();
            bnbUser[nob] = user;
            bnbNumber[nob] = block.number;
            bnbTime[nob].actTime = block.timestamp;
            LET.mint(user, rewardAmount);

            emit BnbGame(address(this), user, nob);
            nob = ++esnInfo.esnNum;
            bnbTime[nob].startTime = block.timestamp;
        }
    }

    mapping(uint256 => uint256) public bnbNumber;
    event BnbGame(address account, address user, uint256 num);
    function AllocateAssets() internal {
        bombInfo[nob].totalAmount = esnInfo.esnAmount;
        bombInfo[nob].userReward = esnInfo.esnAmount.mul(initRate).div(baseRate);
        bombInfo[nob].betLp = esnInfo.esnAmount.mul(betLpRate).div(baseRate);
        bombInfo[nob].letLp = esnInfo.esnAmount.mul(letLpRate).div(baseRate);
        bombInfo[nob].letUserAmount = esnInfo.esnAmount.mul(letUserRate).div(baseRate);
        bombInfo[nob].proAmount = esnInfo.esnAmount.mul(pragmaRate).div(baseRate);

        uint256 lAmount = bombInfo[nob].userReward.add(bombInfo[nob].betLp).add(bombInfo[nob].letLp);
        lAmount = lAmount.add(bombInfo[nob].letUserAmount).add(bombInfo[nob].proAmount);

        bombInfo[nob].luckyAmount = esnInfo.esnAmount.sub(lAmount);
        esnInfo.esnAmount = 0;
    }

    function setRewardAmount(uint256 amount) external onlyOperator {
        require(amount > 0, "amount err");
        rewardAmount = amount;
    }

    function inDaoAmount() internal {
        daoLetUserAmount = daoLetUserAmount.add(bombInfo[nob].letUserAmount);

        if(daoAccount != address(0)) {
            if(daoLetUserAmount > 0 && ILetDao(daoAccount).voteInfo(address(this)) > 0) {
                uint256 value = daoLetUserAmount;
                daoLetUserAmount = 0;
                ILetDao(daoAccount).addBNB(address(this), nob, value);
                rewardToken.safeTransfer(daoAccount, value);

                emit RewardDao(daoAccount, value);
            }
        } else {
            if(daoLetUserAmount > 0) {
                uint256 value = daoLetUserAmount;
                daoLetUserAmount = 0;
                rewardToken.safeTransfer(proAccount, value);
                emit RewardPro(proAccount, value);
            }
        }
    }

    function distReward() internal {
        letUserReward = letUserReward.add(bombInfo[nob].userReward);
        if(address(ldSwap) != address(0)) {
            if(letUserReward > 0 && letUsdt != address(0)) {
                uint256 _let = letUserReward;
                letUserReward = 0;
                rewardToken.safeIncreaseAllowance(address(ldSwap), _let);
                address[] memory path_ = new address[](2);
                path_[0] = address(rewardToken); 
                path_[1] = address(LET);
                uint256 value = ldSwap.swapToken(path_, _let, block.timestamp.add(24 hours));
                totalReward = totalReward.add(value);
                nobReward[nob] = value;
                esnInfo.rewardPerTokenStored = esnInfo.rewardPerTokenStored.add(value.mul(E6).div(esnInfo.totalLPStake));
            }
        }



        if(bombInfo[nob].proAmount > 0) {
            rewardToken.safeTransfer(proAccount, bombInfo[nob].proAmount);
            emit RewardPro(proAccount, bombInfo[nob].proAmount);
        }
    }


    function letSwap() internal {
        swapLetAmount = swapLetAmount.add(bombInfo[nob].letLp);

        if(address(ldSwap) != address(0)) {
            if(swapLetAmount > 0 && letUsdt != address(0)) {
                uint256 _let = swapLetAmount;
                swapLetAmount = 0;
                rewardToken.safeIncreaseAllowance(address(ldSwap), _let);
                address[] memory path_ = new address[](2);
                path_[0] = address(rewardToken); 
                path_[1] = address(LET);
                ldSwap.depositSigleToken(letUsdt, path_, _let, 0, 0, block.timestamp.add(24 hours));
            }
        }
    }

    function betSwap() internal {
        swapBetAmount = swapBetAmount.add(bombInfo[nob].betLp);

        if(address(ldSwap) != address(0)) {
            if(swapBetAmount > 0 && betUsdt != address(0)) {
                uint256 _bet = swapBetAmount;
                swapBetAmount = 0;

                rewardToken.safeIncreaseAllowance(address(ldSwap), _bet);
                address[] memory path_ = new address[](2);
                path_[0] = address(rewardToken); 
                path_[1] = address(BET);
                ldSwap.depositSigleToken(betUsdt, path_, _bet, 0, 0, block.timestamp.add(24 hours));
            }
        }
    }
 
    function luckyReward() internal {
        address user = getLucker();
        if(user == address(0)) {
            user = proAccount;
        }
        luckeyUser[nob].user = user;

        if(bombInfo[nob].luckyAmount > 0) {
            luckeyUser[nob].amount = bombInfo[nob].luckyAmount;
            rewardToken.safeTransfer(user, bombInfo[nob].luckyAmount);
            emit LuckyReward(user, bombInfo[nob].luckyAmount);
        }
    }

    function getLucker() internal returns(address) {
        uint256 len = users[nob].length();
        if(len > 0) {
            uint256 number = 
            uint256(keccak256(abi.encodePacked(
                block.timestamp,
                msg.sender,
                address(this),
                nonce,
                block.number
            ))).mod(len);

            nonce++;
            return users[nob].at(number);
        }
        return address(0);
    }


    function getTotalAmount() external view returns(uint256) {
        return poolInfo.totalAmount;
    }

    function getUserLength(uint256 num) external view returns(uint256) {
        return users[num].length();
    }

    function getUserAddr(uint256 num, uint256 index) external view returns(address, uint256) {
        address user = users[num].at(index);
        return (user, userTotalBet[num][user]); 
    }

    function getUserContains(uint256 num, address user) external view returns(bool) {
        return users[num].contains(user);
    }

    function getBetAmount(uint256 num, address user) external view returns(uint256) {
        return userTotalBet[num][user];
    }

    function updateWeek() public {
        if(address(0) != daoAccount) {
            ILetDao(daoAccount).updateWeek();
        }
    }

    function getWeekUserNum(uint256 wID) external view returns(uint256) {
        return weekUser[wID].length();
    }

    function getWeekUser(uint256 wID, uint256 index) external view returns(address, uint256) {
        address user = weekUser[wID].at(index);
        return (user, totalWeekUserAmount[wID][user]);
    }

    function getWeekUserIn(uint256 wID, address user) external view returns(bool) {
        return weekUser[wID].contains(user);
    }

    function getBnbNum() public view returns(uint256) {
        return nob - 1;
    }

    function getBnbAveTime() external view returns(uint256) {
        if(nob == 1) {
            return 0;
        }
        return bnbTime[nob-1].actTime.sub(bnbTime[1].startTime).div(nob-1);
    }

    function getBetUserNum() external view returns(uint256) {
        return betUser.length();
    }

    function getBetUser(uint256 index) external view returns(address) {
        return betUser.at(index);
    }


    function earned(address account) public view returns (uint256) {
        return
            userInfo[account].balances
                .mul(esnInfo.rewardPerTokenStored.sub(userInfo[account].userRewardPerTokenPaid))
                .div(E6)
                .add(userInfo[account].rewards);
    }

    function initBnbTime(uint256 startTime) external onlyOperator {
        require(!initTime, "has init");
        require(nob == 1, "nob err");
        require(startTime > block.timestamp, "time err");
        initTime = true;
        bnbTime[nob].startTime = startTime;
    }
}
