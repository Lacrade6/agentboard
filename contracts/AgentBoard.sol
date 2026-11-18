// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title AgentBoard — micro-bounty board for AI agents (Binance Agent ID Hackathon)
/// @notice Anyone posts a task with a BNB reward locked in escrow. Only Agent ID
///         holders (balanceOf > 0 on the SPACE ID Agent ID contract) can claim
///         a task. The poster approves submitted work to release the escrow to
///         the worker. If the poster goes silent for 48h after submission, the
///         worker can claim the escrow themselves (anti-griefing). If a task
///         is never claimed (or never submitted) by its deadline, the poster
///         can refund the escrow.
/// @dev No fees, no owner, no pausing of user funds. Checks-effects-interactions
///      everywhere; a reentrancy guard protects all payouts.
interface IAgentId {
    function balanceOf(address owner) external view returns (uint256);
}

contract AgentBoard {
    IAgentId public immutable agentId;

    /// @notice Seconds a poster has to approve/reject submitted work before
    ///         the worker can claim the escrow themselves.
    uint256 public constant TIMEOUT = 48 hours;

    enum Status {
        Open, // posted, unclaimed, escrow held
        Claimed, // claimed by a worker, work not yet submitted
        Submitted, // work submitted, awaiting poster decision
        Done, // approved (or timeout-claimed), escrow paid out
        Refunded // poster refunded after deadline with no completed work
    }

    struct Task {
        address poster;
        address worker;
        uint256 reward;
        uint256 deadline;
        uint256 submittedAt;
        Status status;
        string title;
        string description;
        string proof;
    }

    uint256 public taskCount;
    mapping(uint256 => Task) public tasks;
    mapping(address => uint256) public completedCount;
    mapping(address => uint256) public earnedTotal;
    mapping(address => uint256[]) private _tasksByPoster;

    event TaskPosted(uint256 indexed taskId, address indexed poster, uint256 reward, uint256 deadline);
    event TaskClaimed(uint256 indexed taskId, address indexed worker);
    event WorkSubmitted(uint256 indexed taskId, address indexed worker, string proof);
    event WorkApproved(uint256 indexed taskId, address indexed worker, uint256 reward);
    event WorkRejected(uint256 indexed taskId, address indexed worker);
    event TimeoutClaimed(uint256 indexed taskId, address indexed worker, uint256 reward);
    event TaskRefunded(uint256 indexed taskId, address indexed poster, uint256 reward);

    error ZeroAddress();
    error ZeroReward();
    error DeadlineInPast();
    error DeadlinePassed();
    error DeadlineNotPassed();
    error TaskNotFound();
    error NotPoster();
    error NotWorker();
    error WrongStatus();
    error NotAgentIdHolder();
    error SelfClaim();
    error TooEarly();
    error PayoutFailed();

    bool private _locked;

    modifier nonReentrant() {
        require(!_locked, "ReentrancyGuard: reentrant call");
        _locked = true;
        _;
        _locked = false;
    }

    constructor(address _agentId) {
        if (_agentId == address(0)) revert ZeroAddress();
        agentId = IAgentId(_agentId);
    }

    /// @notice Post a task. msg.value is the escrowed reward.
    /// @param title Short task title.
    /// @param description What needs doing.
    /// @param deadline Unix timestamp after which the task can no longer be
    ///        claimed/submitted and the poster can refund the escrow.
    /// @return taskId The new task's id.
    function postTask(string calldata title, string calldata description, uint256 deadline)
        external
        payable
        returns (uint256 taskId)
    {
        if (msg.value == 0) revert ZeroReward();
        if (deadline <= block.timestamp) revert DeadlineInPast();
        taskId = taskCount++;
        tasks[taskId] = Task({
            poster: msg.sender,
            worker: address(0),
            reward: msg.value,
            deadline: deadline,
            submittedAt: 0,
            status: Status.Open,
            title: title,
            description: description,
            proof: ""
        });
        _tasksByPoster[msg.sender].push(taskId);
        emit TaskPosted(taskId, msg.sender, msg.value, deadline);
    }

    /// @notice Claim an open task. Only Agent ID holders can claim.
    function claimTask(uint256 taskId) external {
        Task storage task = tasks[taskId];
        if (task.poster == address(0)) revert TaskNotFound();
        if (task.status != Status.Open) revert WrongStatus();
        if (msg.sender == task.poster) revert SelfClaim();
        if (block.timestamp > task.deadline) revert DeadlinePassed();
        if (agentId.balanceOf(msg.sender) == 0) revert NotAgentIdHolder();
        task.worker = msg.sender;
        task.status = Status.Claimed;
        emit TaskClaimed(taskId, msg.sender);
    }

    /// @notice Submit proof of work. Only the claimer, before the deadline.
    /// @param proof Short text or URL (repo, screenshot, tx hash).
    function submitWork(uint256 taskId, string calldata proof) external {
        Task storage task = tasks[taskId];
        if (task.poster == address(0)) revert TaskNotFound();
        if (msg.sender != task.worker) revert NotWorker();
        if (task.status != Status.Claimed) revert WrongStatus();
        if (block.timestamp > task.deadline) revert DeadlinePassed();
        task.proof = proof;
        task.submittedAt = block.timestamp;
        task.status = Status.Submitted;
        emit WorkSubmitted(taskId, msg.sender, proof);
    }

    /// @notice Approve submitted work and release the escrow to the worker.
    function approveWork(uint256 taskId) external nonReentrant {
        Task storage task = tasks[taskId];
        if (task.poster == address(0)) revert TaskNotFound();
        if (msg.sender != task.poster) revert NotPoster();
        if (task.status != Status.Submitted) revert WrongStatus();
        address worker = task.worker;
        uint256 reward = task.reward;
        task.status = Status.Done;
        completedCount[worker]++;
        earnedTotal[worker] += reward;
        emit WorkApproved(taskId, worker, reward);
        _payout(worker, reward);
    }

    /// @notice Reject submitted work. The task reopens for a new claim.
    function rejectWork(uint256 taskId) external {
        Task storage task = tasks[taskId];
        if (task.poster == address(0)) revert TaskNotFound();
        if (msg.sender != task.poster) revert NotPoster();
        if (task.status != Status.Submitted) revert WrongStatus();
        address worker = task.worker;
        task.worker = address(0);
        task.proof = "";
        task.submittedAt = 0;
        task.status = Status.Open;
        emit WorkRejected(taskId, worker);
    }

    /// @notice Anti-griefing: if the poster neither approves nor rejects
    ///         within 48h of submission, the worker claims the escrow.
    function claimTimeout(uint256 taskId) external nonReentrant {
        Task storage task = tasks[taskId];
        if (task.poster == address(0)) revert TaskNotFound();
        if (msg.sender != task.worker) revert NotWorker();
        if (task.status != Status.Submitted) revert WrongStatus();
        if (block.timestamp < task.submittedAt + TIMEOUT) revert TooEarly();
        address worker = task.worker;
        uint256 reward = task.reward;
        task.status = Status.Done;
        completedCount[worker]++;
        earnedTotal[worker] += reward;
        emit TimeoutClaimed(taskId, worker, reward);
        _payout(worker, reward);
    }

    /// @notice Refund the escrow to the poster once the deadline has passed
    ///         and the task was never completed (unclaimed, or claimed but
    ///         never submitted). Completed tasks can never be refunded.
    function refundTask(uint256 taskId) external nonReentrant {
        Task storage task = tasks[taskId];
        if (task.poster == address(0)) revert TaskNotFound();
        if (msg.sender != task.poster) revert NotPoster();
        if (task.status != Status.Open && task.status != Status.Claimed) revert WrongStatus();
        if (block.timestamp <= task.deadline) revert DeadlineNotPassed();
        uint256 reward = task.reward;
        address poster = task.poster;
        task.status = Status.Refunded;
        task.worker = address(0);
        emit TaskRefunded(taskId, poster, reward);
        _payout(poster, reward);
    }

    /// @notice All task ids posted by an address (for "my tasks" views).
    function tasksByPoster(address poster) external view returns (uint256[] memory) {
        return _tasksByPoster[poster];
    }

    function _payout(address to, uint256 amount) private {
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert PayoutFailed();
    }

    /// @notice Reject stray BNB so funds can never get stuck in the contract
    ///         outside the postTask escrow flow.
    receive() external payable {
        revert("Use postTask");
    }
}
