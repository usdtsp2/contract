// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "ReentrancyGuard.sol";

// Define the TRC-20 interface
interface ITRC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract TRC20AdvancedToken is ITRC20, ReentrancyGuard {
    // Token details
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;

    address public owner;
    uint256 public buyFee;
    uint256 public sellFee;
    uint256 public cooldownTime = 30;
    uint256 public maximumFee;
    bool public paused;
    address public upgradedAddress;
    bool public deprecated;

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
    event ContractDeprecated(address upgradedAddress);
    event DestroyedBlacklistedFunds(address indexed blacklistedUser, uint256 amount);
    event PauseStateChanged(bool isPaused);

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

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply
    ) {
        require(bytes(_name).length > 0, "Name cannot be empty");
        require(bytes(_symbol).length > 0, "Symbol cannot be empty");
        require(_initialSupply > 0, "Initial supply must be greater than 0");

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

    function transfer(address to, uint256 value) public notBlacklisted(msg.sender) notFrozen(msg.sender) whenNotPaused override returns (bool) {
        require(balances[msg.sender] >= value, "Insufficient balance");
        require(block.timestamp >= _lastTransferTime[msg.sender] + cooldownTime, "Cooldown period active");

        uint256 fee = (value * buyFee) / 10000;
        uint256 netValue = value - fee;

        balances[msg.sender] -= value;
        balances[to] += netValue;
        if (fee > 0) {
            balances[owner] += fee;
        }
        _lastTransferTime[msg.sender] = block.timestamp;

        emit Transfer(msg.sender, to, netValue);
        if (fee > 0) {
            emit Transfer(msg.sender, owner, fee);
        }

        return true;
    }

    function approve(address spender, uint256 value) public override returns (bool) {
        allowances[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public notBlacklisted(from) notFrozen(from) whenNotPaused override returns (bool) {
        require(balances[from] >= value, "Insufficient balance");
        require(allowances[from][msg.sender] >= value, "Allowance exceeded");
        require(block.timestamp >= _lastTransferTime[from] + cooldownTime, "Cooldown period active");

        uint256 fee = (value * sellFee) / 10000;
        uint256 netValue = value - fee;

        balances[from] -= value;
        balances[to] += netValue;
        if (fee > 0) {
            balances[owner] += fee;
        }
        allowances[from][msg.sender] -= value;
        _lastTransferTime[from] = block.timestamp;

        emit Transfer(from, to, netValue);
        if (fee > 0) {
            emit Transfer(from, owner, fee);
        }

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
        require(_buyFee <= 10000, "Buy fee must be <= 100%");
        require(_sellFee <= 10000, "Sell fee must be <= 100%");

        buyFee = _buyFee;
        sellFee = _sellFee;
        emit FeesUpdated(buyFee, sellFee);
    }

    function setMaxFee(uint256 newMaxFee) public onlyOwner {
        maximumFee = newMaxFee;
    }

    function deprecate(address _upgradedAddress) public onlyOwner {
        require(_upgradedAddress != address(0), "Invalid address");
        deprecated = true;
        upgradedAddress = _upgradedAddress;
        emit ContractDeprecated(_upgradedAddress);
    }

    function destroyBlacklistedFunds(address _blacklistedUser) public onlyOwner {
        require(_blacklisted[_blacklistedUser], "Not blacklisted");
        uint256 dirtyFunds = balances[_blacklistedUser];
        balances[_blacklistedUser] = 0;
        totalSupply -= dirtyFunds;
        emit DestroyedBlacklistedFunds(_blacklistedUser, dirtyFunds);
    }

    function pause() external onlyOwner {
        paused = true;
        emit PauseStateChanged(true);
    }

    function unpause() external onlyOwner {
        paused = false;
        emit PauseStateChanged(false);
    }

    function stake(uint256 amount) public nonReentrant {
        require(amount > 0, "Cannot stake 0");
        require(balances[msg.sender] >= amount, "Insufficient balance");

        balances[msg.sender] -= amount;
        _stakedBalances[msg.sender] += amount;

        if (_stakedBalances[msg.sender] == amount) {
            stakerAddresses.push(msg.sender);
        }

        emit Stake(msg.sender, amount);
    }

    function unstake(uint256 amount) public nonReentrant {
        require(amount > 0, "Cannot unstake 0");
        require(
            _stakedBalances[msg.sender] >= amount,
            "Insufficient staked balance"
        );

        _stakedBalances[msg.sender] -= amount;
        balances[msg.sender] += amount;

        emit Unstake(msg.sender, amount);
    }

    function distributeRewards(uint256 totalRewards) public onlyOwner nonReentrant {
        require(totalRewards > 0, "No rewards to distribute");
        uint256 totalStaked = getTotalStaked();
        require(totalStaked > 0, "No staked tokens");

        for (uint256 i = 0; i < stakerAddresses.length; i++) {
            address staker = stakerAddresses[i];
            uint256 reward = (totalRewards * _stakedBalances[staker]) /
                totalStaked;
            _stakingRewards[staker] += reward;
        }
        emit RewardsDistributed(totalRewards);
    }

    function claimRewards() public nonReentrant {
        uint256 rewards = _stakingRewards[msg.sender];
        require(rewards > 0, "No rewards to claim");

        _stakingRewards[msg.sender] = 0;
        balances[msg.sender] += rewards;

        emit Transfer(address(0), msg.sender, rewards);
    }

    function getTotalStaked() public view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < stakerAddresses.length; i++) {
            total += _stakedBalances[stakerAddresses[i]];
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
