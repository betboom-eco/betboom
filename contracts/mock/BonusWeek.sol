// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "../../libraries/SafeMath.sol";
import "../common/Op.sol";
import "../../libraries/EnumerableSet.sol";
import "../../interfaces/IERC20.sol";
import "../../libraries/SafeERC20.sol";
import "../../interfaces/IPool.sol";
import "../../interfaces/ILetDaoSwap.sol";
import "../../interfaces/ILetDao.sol";
import "../../interfaces/INFTPool.sol";

contract BonusWeek is Op {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    event TransferTo(address token, address account, uint256 amount);
    event AddBonus(address gamePool, uint256 nobNum, uint256 amount, uint256 num, uint256 moreAmount, uint256 rValue);
    event ClaimBonus(address user, address gamePool, uint256 amount, uint256 num);
    event ClaimWeekBonus(address user, address gamePool, uint256 amount, uint256 num);
    event SortWeekUserBonus(address gamePool, uint256 wID, uint256 value);
    event AddWeekBonus(uint256 wID, uint256 amount);

    struct BInfo {
        uint256 num;
        uint256 totalAmount;
        bool isAdd;
    }

    struct UserInfo {
        uint256 amount;
        uint256 haveClaim;
        uint256 claimNum;
        uint256[] period;
        uint256[] total;
    }

    struct UserClaim {
        uint256 claimAmount;
        uint256 blockNum;
        uint256 time;
        uint256[] period;
    }


    struct WeekBonus {
        uint256 totalAmount;
        uint256 letBonus;
        address[] weekPool;
        bool isAdd;
    }

    struct WeekGame {
        uint256 letBonus;
        bool isAdd;
        bool isSort;
    }

    uint256 public totalID;
    uint256 public bonusUserNumber = 100;
    address public bonusAccount;
    uint256 public weekBonusAmount = 2000e18;
    address public daoAccount;
    uint256 public weekNumber = 100;

    IERC20 public LET;
    ILetDaoSwap public letSwap;  
    INFTPool public nftPool;  

    mapping(address => mapping(uint256 => BInfo)) public bInfo;
    mapping(address => mapping(uint256 => uint256)) public addGAmount;
    mapping(uint256 => address) public idToPool;
    mapping(address => uint256) public poolToID;
    mapping(address => mapping(uint256 => EnumerableSet.AddressSet)) poolNobUser;
    mapping(address => uint256[]) hasBonus;
    mapping(address => mapping(address => UserInfo)) userInfo;
    mapping(address => mapping(uint256 => mapping(address => uint256))) public gameNobAmount;
    mapping(address => mapping(address => mapping(uint256 => UserClaim))) userClaim;
    mapping(uint256 => uint256) rewardRate;
    mapping(uint256 => mapping(address => WeekGame)) public weekGame;
    mapping(uint256 => WeekBonus)  weekBonus;
    mapping(address => mapping(address => UserInfo)) weekUserInfo;
    mapping(address => mapping(address => mapping(uint256 => UserClaim))) weekUserClaim;
    mapping(uint256 => mapping(address => EnumerableSet.AddressSet)) weekUser;
    mapping(address => mapping(address => mapping(uint256 => uint256))) public usertotalWeekAmount;


    constructor(
        address letToken
    ) {
        LET = IERC20(letToken);
        _init();
    }

    function addPools(address pool) external onlyOperator {
        require(pool != address(0), "not zero address");
        require(poolToID[pool] == 0, "has add");

        ++totalID;
        idToPool[totalID] = pool;
        poolToID[pool] = totalID;
    }

    modifier onlyAuth {
        require(msg.sender == owner() || msg.sender == bonusAccount, "no permission");
        _;
    }

    function setBonusAccount(address account) external onlyOperator {
        require(account > address(0), "not zero address");
        bonusAccount = account;
    }

    function setBonusUserNumber(uint256 num) external onlyOperator {
        require(num > 0 && num <= 100, "num err");
        bonusUserNumber = num;
    }

    function setSwap(address swap) external onlyOperator {
        letSwap = ILetDaoSwap(swap);
    }

    function setNftPool(address nPool) external onlyOperator {
        nftPool = INFTPool(nPool);
    }

    function setWeekBonusAmount(uint256 amount) external onlyOperator {
        require(amount > 0, "amount err");

        weekBonusAmount = amount;
    }


    function setDaoAccount(address account) external onlyOperator {
        daoAccount = account;
    }

    function setWeekNumber(uint256 num) external onlyOperator {
        require(num > 0, "num err");
        weekNumber = num;
    }    


    function addBonusForm(
        address gamePool,
        uint256 amount
    ) external {
        require(msg.sender == address(letSwap), "not letSwap");
        uint256 nob = IPool(gamePool).nob();
        addGAmount[gamePool][nob] = addGAmount[gamePool][nob].add(amount);
    }

    function addBonus(
        address gamePool,
        uint256 nobNum, 
        uint256 amount,
        address[] memory accounts
    ) external onlyAuth 
    {
        uint256 amount0 = amount;
        uint256 num = checkBonus(gamePool, nobNum, amount, accounts);
        bInfo[gamePool][nobNum].isAdd = true;
        amount = addGAmount[gamePool][nobNum].add(amount);
        
        uint256 value;
        for(uint256 i = 0; i < accounts.length; i++) {
            address user = accounts[i];
            if(poolNobUser[gamePool][nobNum].contains(user)) {
                revert("repeat");   
            }
            
            uint256 amount1 = IPool(gamePool).getBetAmount(nobNum, user);
            if(i !=  accounts.length - 1) {
                uint256 amount2 = IPool(gamePool).getBetAmount(nobNum, accounts[i+1]);
                if(amount1 < amount2 || amount1 == 0 || amount2 == 0) {
                    revert("sort err");
                }
            }
            uint256 rAmount = amount.mul(getRate(i+1)).div(baseRate);

            value = value.add(rAmount);

            poolNobUser[gamePool][nobNum].add(user);
            gameNobAmount[gamePool][nobNum][user] = rAmount;
            userInfo[gamePool][user].amount 
                = userInfo[gamePool][user].amount.add(rAmount); 
            userInfo[gamePool][user].period.push(nobNum);
            userInfo[gamePool][user].total.push(nobNum);
        }

        bInfo[gamePool][nobNum].num = num;
        bInfo[gamePool][nobNum].totalAmount = amount;
        hasBonus[gamePool].push(nobNum);     

        if(amount0 > 0) {
            LET.safeTransferFrom(msg.sender, address(this), amount0);
        }

        uint256 rValue;
        if(value > amount) {
            rValue = value.sub(amount);
            LET.safeTransfer(msg.sender, rValue);
        }

        emit AddBonus(gamePool, nobNum, amount, accounts.length, amount0, rValue);
    }

    function addWeekBonus(
        uint256 wID
    ) external onlyAuth {
        checkWeek(wID);
        weekBonus[wID].isAdd = true;

        weekBonus[wID].weekPool = getWeekPool(wID);
        (uint256 _decay, uint256 _base) = ILetDao(daoAccount).getDecay(wID);
        uint256 _weekBonusAmount = weekBonusAmount.mul(_decay).div(_base);
        weekBonus[wID].letBonus = _weekBonusAmount;

        for(uint256 i = 0; i < weekBonus[wID].weekPool.length; i++) {
            uint256 value = getPoolAmount(weekBonus[wID].weekPool[i], wID);
            weekBonus[wID].totalAmount = value.add(weekBonus[wID].totalAmount);
        }

        require(weekBonus[wID].totalAmount > 0, "no vote");
        for(uint256 i = 0; i < weekBonus[wID].weekPool.length; i++) {   
            uint256 _value = getPoolAmount(weekBonus[wID].weekPool[i], wID);
            weekGame[wID][weekBonus[wID].weekPool[i]].letBonus =     
                _weekBonusAmount.
                mul(_value).
                div(weekBonus[wID].totalAmount);
            if(_value > 0) {
                require(weekGame[wID][weekBonus[wID].weekPool[i]].letBonus > 0, "weekBonusAmount too small");
            }
            weekGame[wID][weekBonus[wID].weekPool[i]].isAdd = true;
        }
        LET.mint(address(this), _weekBonusAmount);
        emit AddWeekBonus(wID, _weekBonusAmount);
    }

    function transferTo(address token, address account, uint256 amount) public onlyOwner {
        require(IERC20(token).balanceOf(address(this)) >= amount, "not enough");
        require(account != address(0), "not zero address");

        IERC20(token).safeTransfer(account, amount);
        
        emit TransferTo(token, account, amount);
    }

    function sortWeekUserBonus(
        uint256 wID, 
        address gamePool, 
        address[] memory users
    ) external onlyAuth {
        checkWeekUser(wID, gamePool, users);
        weekGame[wID][gamePool].isSort = true;

        uint256 value;
        for(uint256 i = 0; i < users.length; i++) {
            address user = users[i];

            if(weekUser[wID][gamePool].contains(user)) {
                revert("user err");
            }

            uint256 amount1 = IPool(gamePool).totalWeekUserAmount(wID, user);

            if(i !=  users.length - 1) {
                uint256 amount2 = IPool(gamePool).totalWeekUserAmount(wID, users[i+1]);
                if(amount1 < amount2 || amount1 == 0 || amount2 == 0) {
                    revert("sort err");
                }
            }

            uint256 rAmount = weekGame[wID][gamePool].letBonus.mul(getRate(i+1)).div(baseRate);
            value = value.add(rAmount);

            weekUserInfo[user][gamePool].amount = weekUserInfo[user][gamePool].amount.add(rAmount);
            weekUserInfo[user][gamePool].period.push(wID);
            weekUserInfo[user][gamePool].total.push(wID);

            usertotalWeekAmount[user][gamePool][wID] = rAmount;

            weekUser[wID][gamePool].add(user);
        }

        require(value <= weekGame[wID][gamePool].letBonus, "value err");
        uint256 amount0 = weekGame[wID][gamePool].letBonus.sub(value);
        if(amount0 > 0) {
            LET.safeTransfer(msg.sender, amount0);
        }

        emit SortWeekUserBonus(gamePool, wID, value);
    }


    function claimWeekBonus(address gamePool) external {
        uint256 amount = weekUserInfo[msg.sender][gamePool].amount;
        require(amount > 0, "no amount");
        weekUserInfo[msg.sender][gamePool].amount = 0;
        weekUserInfo[msg.sender][gamePool].haveClaim = weekUserInfo[msg.sender][gamePool].haveClaim.add(amount);
        uint256 num = ++weekUserInfo[msg.sender][gamePool].claimNum;

        weekUserClaim[msg.sender][gamePool][num].claimAmount = amount;
        weekUserClaim[msg.sender][gamePool][num].blockNum = block.number;
        weekUserClaim[msg.sender][gamePool][num].time = block.timestamp;
        weekUserClaim[msg.sender][gamePool][num].period = weekUserInfo[msg.sender][gamePool].period;

        for(uint256 i = 0; i < weekUserInfo[msg.sender][gamePool].period.length; i++) {
            weekUserInfo[msg.sender][gamePool].period.pop();
        }

        LET.safeTransfer(msg.sender, amount);
        emit ClaimWeekBonus(msg.sender, gamePool, amount, num);
    }

    function checkBonus(
        address gamePool,
        uint256 nobNum, 
        uint256 amount,
        address[] memory accounts
    ) public view returns(uint256) {
        amount = addGAmount[gamePool][nobNum].add(amount);
        IPool pool = IPool(gamePool);
        uint256 gLen = pool.getUserLength(nobNum);
        require(
            0 < nobNum && nobNum < pool.nob() &&
            poolToID[gamePool] != 0 &&
            accounts.length <= gLen &&
            !bInfo[gamePool][nobNum].isAdd &&
            amount > 0
            , "param err"
        );

        uint256 num;
        if(gLen >= bonusUserNumber) {
            require(
                accounts.length == bonusUserNumber && 
                accounts.length > 0, 
                "length err"
            );
            num = bonusUserNumber;
        } else {
            require(
                accounts.length < bonusUserNumber && 
                accounts.length > 0 &&
                gLen == accounts.length, 
                "length err"
            );
            num = gLen;
        }
 

        return num;
    }

    function getHasBonus(address gamePool) external view returns(uint256[] memory) {
        return hasBonus[gamePool];
    }

    function claimBonus(address gamePool) external {
        uint256 amount = userInfo[gamePool][msg.sender].amount;
        require(amount > 0, "no amount");
        userInfo[gamePool][msg.sender].amount = 0;
        userInfo[gamePool][msg.sender].haveClaim = userInfo[gamePool][msg.sender].haveClaim.add(amount);
        uint256 num = ++userInfo[gamePool][msg.sender].claimNum;

        userClaim[gamePool][msg.sender][num].claimAmount = amount;
        userClaim[gamePool][msg.sender][num].blockNum = block.number;
        userClaim[gamePool][msg.sender][num].time = block.timestamp;
        userClaim[gamePool][msg.sender][num].period = userInfo[gamePool][msg.sender].period;

        for(uint256 i = 0; i < userInfo[gamePool][msg.sender].period.length; i++) {
            userInfo[gamePool][msg.sender].period.pop();
        }

        LET.safeTransfer(msg.sender, amount);

        emit ClaimBonus(msg.sender, gamePool, amount, num);
    }

    function getUserClaim(
        address gamePool, 
        address user, 
        uint256 num
    ) external view returns(UserClaim memory) {
        return userClaim[gamePool][user][num];
    }

    function getUserInfo(
        address gamePool, 
        address user 
    ) external view returns(UserInfo memory) {
        return userInfo[gamePool][user];
    }

    function _init() private {
        rewardRate[1] = 3000;
        rewardRate[2] = 2000;
        rewardRate[3] = 1500;
        rewardRate[4] = 1000;
        rewardRate[5] = 500;
        rewardRate[6] = 400;
        rewardRate[7] = 300;
        rewardRate[8] = 200;
        rewardRate[9] = 100;
        rewardRate[10] = 50;
    }

    function getRate(uint256 rank) public view returns(uint256) {
        if(rank > 0 && rank <= 10) {
            return rewardRate[rank];
        } else if(10 < rank && rank <= 100) {
            return 10;
        }  else {
            return 0;
        }
    }

    function getWeekBonus(uint256 wID) external view returns(WeekBonus memory) {
        return weekBonus[wID];
    }

    function getWeekBonusPoolNum(uint256 wID) external view returns(uint256) {
        return weekBonus[wID].weekPool.length;
    }
    

    function getWeekUserClaim(
        address user, 
        address gamePool, 
        uint256 num
    ) external view returns(UserClaim memory) {
        return weekUserClaim[user][gamePool][num];
    }

    function checkWeekUser(        
        uint256 wID, 
        address gamePool, 
        address[] memory users
    ) public view returns(uint256 num) {
        require(poolToID[gamePool] != 0, "not add pool");
        require(weekGame[wID][gamePool].isAdd, "not add bonus");
        uint256 gLen = IPool(gamePool).getWeekUserNum(wID);
        require(gLen >= users.length, "user num err");

        if(gLen >= weekNumber) {
            require(users.length > 0 && weekNumber == users.length, "length err");
            num = weekNumber;
        } else {
            require(
                users.length > 0 && 
                weekNumber > users.length &&
                gLen == users.length,
                "length err"
            );
            num = gLen;
        }

        require(weekGame[wID][gamePool].letBonus > 0, "no bonus");
        require(!weekGame[wID][gamePool].isSort, "has sort");

        return num;
    }


    

    function checkWeek(        
        uint256 wID
    ) public view returns(bool) {
        require(!weekBonus[wID].isAdd, "has add");
        require(ILetDao(daoAccount).getWeekPoolNum(wID) > 0, "no play");

        return true;
    }
    

    function getWeekPool(uint256 wID) public view returns(address[] memory) {
        return ILetDao(daoAccount).getWeekPool(wID);
    }

    function getTotalAmount(uint256 wID) public view returns(uint256, address[] memory) {
        uint256 len = ILetDao(daoAccount).getWeekPoolNum(wID);
        address[] memory weekPool = new address[](len);
        weekPool = getWeekPool(wID);
  
        uint256 total;
        for(uint256 i = 0; i < len; i++) {
            total = getPoolAmount(weekPool[i], wID).add(total);
        }

        return (total, weekPool);
    }

    function getPoolAmount(address gamePool, uint256 wID) public view returns(uint256) {
        return ILetDao(daoAccount).weekGameVote(wID, gamePool);
    }



    function getdecay(uint256 wID) public view returns(uint256, uint256) {
        return ILetDao(daoAccount).getDecay(wID);
    }

    function getWeekUserInfo(address user, address gamePool) external view returns(UserInfo memory) {
        return weekUserInfo[user][gamePool];
    }

    function getUserWeekNum(address user, address gamePool) external view returns(uint256) {
        return weekUserInfo[user][gamePool].period.length;
    }
    function getWeekUserNum(uint256 wID, address gamePool) external view returns(uint256) {
        return weekUser[wID][gamePool].length();
    }

    function getWeekUser(
        uint256 wID, 
        address gamePool, 
        uint256 index
    ) external view returns(address) {
        return weekUser[wID][gamePool].at(index);
    }

    function getweekUserContains(
        uint256 wID, 
        address gamePool, 
        address user
    ) external view returns(bool) {
        return weekUser[wID][gamePool].contains(user);
    }

    function getPoolNobUserNum(address gamePool, uint256 nobNum) external view returns(uint256) {
        return poolNobUser[gamePool][nobNum].length();
    }

    function getPoolNobUser(
        address gamePool, 
        uint256 nobNum, 
        uint256 index
    ) external view returns(address) {
        return poolNobUser[gamePool][nobNum].at(index);
    }

}