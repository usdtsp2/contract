// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

// Define the TRC-20 interface
interface ITRC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract TRC20AdvancedToken is ITRC20 {
    // Token details
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;

    address public owner;
    uint256 public buyFee;
    uint256 public sellFee;
    uint256 public cooldownTime = 30;

    mapping(address => uint256) private balances;
    mapping(address => mapping(address => uint256)) private allowances;
    mapping(address => bool) private _blacklisted;
    mapping(address => bool) private _frozen;
    mapping(address => uint256) private _lastTransferTime;
    mapping(address => uint256) private _stakedBalances;
    mapping(address => uint256) private _stakingRewards;
    address[] private stakerAddresses;

    // Events
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event BlacklistUpdated(address indexed user, bool isBlacklisted);
    event AccountFrozen(address indexed user, bool isFrozen);
    event FeesUpdated(uint256 buyFee, uint256 sellFee);
    event Stake(address indexed user, uint256 amount);
    event Unstake(address indexed user, uint256 amount);
    event RewardsDistributed(uint256 totalRewards);

    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not the owner");
        _;
    }

    modifier notBlacklisted(address user) {
        require(!_blacklisted[user], "User is blacklisted");
        _;
    }

    modifier notFrozen(address user) {
        require(!_frozen[user], "Account is frozen");
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply
    ) {
        name = _name;
        symbol = _symbol;
        totalSupply = _initialSupply * (10 ** decimals);
        balances[msg.sender] = totalSupply;
        owner = msg.sender;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    // TRC-20 Functions
    function balanceOf(address account) public view override returns (uint256) {
        return balances[account];
    }

    function totalSupply() external view override returns (uint256) {
        return totalSupply;
    }

    function transfer(address to, uint256 value) public notBlacklisted(msg.sender) notFrozen(msg.sender) override returns (bool) {
        require(balances[msg.sender] >= value, "Insufficient balance");
        require(block.timestamp >= _lastTransferTime[msg.sender] + cooldownTime, "Cooldown period active");

        balances[msg.sender] -= value;
        balances[to] += value;
        _lastTransferTime[msg.sender] = block.timestamp;

        emit Transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) public override returns (bool) {
        allowances[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public notBlacklisted(from) notFrozen(from) override returns (bool) {
        require(balances[from] >= value, "Insufficient balance");
        require(allowances[from][msg.sender] >= value, "Allowance exceeded");
        require(block.timestamp >= _lastTransferTime[from] + cooldownTime, "Cooldown period active");

        balances[from] -= value;
        balances[to] += value;
        allowances[from][msg.sender] -= value;
        _lastTransferTime[from] = block.timestamp;

        emit Transfer(from, to, value);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return allowances[owner][spender];
    }

    // Advanced features
    function updateBlacklist(
        address user,
        bool isBlacklisted
    ) public onlyOwner {
        _blacklisted[user] = isBlacklisted;
        emit BlacklistUpdated(user, isBlacklisted);
    }

    function freezeAccount(address user, bool isFrozen) public onlyOwner {
        _frozen[user] = isFrozen;
        emit AccountFrozen(user, isFrozen);
    }

    function setTransactionFees(
        uint256 _buyFee,
        uint256 _sellFee
    ) public onlyOwner {
        buyFee = _buyFee;
        sellFee = _sellFee;
        emit FeesUpdated(buyFee, sellFee);
    }

    function stake(uint256 amount) public {
        require(amount > 0, "Cannot stake 0");
        require(balances[msg.sender] >= amount, "Insufficient balance");

        balances[msg.sender] -= amount;
        _stakedBalances[msg.sender] += amount;

        emit Stake(msg.sender, amount);
    }

    function unstake(uint256 amount) public {
        require(amount > 0, "Cannot unstake 0");
        require(
            _stakedBalances[msg.sender] >= amount,
            "Insufficient staked balance"
        );

        _stakedBalances[msg.sender] -= amount;
        balances[msg.sender] += amount;

        emit Unstake(msg.sender, amount);
    }

    function distributeRewards(uint256 totalRewards) public onlyOwner {
        require(totalRewards > 0, "No rewards to distribute");
        uint256 totalStaked = getTotalStaked();

        for (uint256 i = 0; i < getNumberOfStakers(); i++) {
            address staker = getStakerByIndex(i);
            uint256 reward = (totalRewards * _stakedBalances[staker]) /
                totalStaked;
            _stakingRewards[staker] += reward;
        }
        emit RewardsDistributed(totalRewards);
    }

    function claimRewards() public {
        uint256 rewards = _stakingRewards[msg.sender];
        require(rewards > 0, "No rewards to claim");

        _stakingRewards[msg.sender] = 0;
        balances[msg.sender] += rewards;
    }

    function getTotalStaked() public view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < getNumberOfStakers(); i++) {
            total += _stakedBalances[getStakerByIndex(i)];
        }
        return total;
    }

    /**
     * @dev Returns the staker address at a given index.
     * @param index The index of the staker in the staker list.
     * @return The address of the staker at the specified index.
     */
    function getStakerByIndex(uint256 index) public view returns (address) {
        require(index < stakerAddresses.length, "Index out of bounds");
        return stakerAddresses[index];
    }

    /**
     * @dev Returns the total number of stakers.
     * @return The number of stakers.
     */
    function getNumberOfStakers() public view returns (uint256) {
        return stakerAddresses.length;
    }
}
