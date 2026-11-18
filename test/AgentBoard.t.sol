// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/AgentBoard.sol";
import "../contracts/MockAgentId.sol";

/// @notice A worker contract that tries to re-enter approveWork from its
///         receive() hook. The guard must block it; the payout must happen
///         exactly once.
contract ReentrantWorker {
    AgentBoard public board;
    uint256 public taskId;
    bool public attacked;

    constructor(AgentBoard _board) {
        board = _board;
    }

    function setTask(uint256 _taskId) external {
        taskId = _taskId;
    }

    receive() external payable {
        if (!attacked) {
            attacked = true;
            try board.approveWork(taskId) {} catch {}
        }
    }
}

contract AgentBoardTest is Test {
    MockAgentId agentId;
    AgentBoard board;

    address poster = address(0xA11CE);
    address worker = address(0xB0B);
    address worker2 = address(0xC0FFEE);
    address stranger = address(0xDEAD);

    uint256 constant REWARD = 0.1 ether;
    uint256 deadline;

    function setUp() public {
        agentId = new MockAgentId();
        board = new AgentBoard(address(agentId));
        agentId.mint(worker);
        agentId.mint(worker2);
        deadline = block.timestamp + 7 days;
        vm.deal(poster, 10 ether);
        vm.deal(worker, 1 ether);
        vm.deal(worker2, 1 ether);
    }

    function _postTask() internal returns (uint256) {
        vm.prank(poster);
        return board.postTask{value: REWARD}("Find a free mint", "Find a verified free BSC mint", deadline);
    }

    function _postClaimSubmit(uint256 taskId) internal {
        vm.prank(worker);
        board.claimTask(taskId);
        vm.prank(worker);
        board.submitWork(taskId, "https://example.com/proof");
    }

    // --- posting ---

    function testPostTask() public {
        uint256 id = _postTask();
        assertEq(id, 0);
        assertEq(board.taskCount(), 1);
        (address p, address w, uint256 r, uint256 d, uint256 s, AgentBoard.Status st,,,) =
            board.tasks(id);
        assertEq(p, poster);
        assertEq(w, address(0));
        assertEq(r, REWARD);
        assertEq(d, deadline);
        assertEq(s, 0);
        assertEq(uint8(st), uint8(AgentBoard.Status.Open));
        assertEq(address(board).balance, REWARD);
    }

    function testPostTaskZeroValueReverts() public {
        vm.prank(poster);
        vm.expectRevert(AgentBoard.ZeroReward.selector);
        board.postTask{value: 0}("t", "d", deadline);
    }

    function testPostTaskPastDeadlineReverts() public {
        vm.prank(poster);
        vm.expectRevert(AgentBoard.DeadlineInPast.selector);
        board.postTask{value: REWARD}("t", "d", block.timestamp);
    }

    function testTasksByPoster() public {
        _postTask();
        _postTask();
        uint256[] memory ids = board.tasksByPoster(poster);
        assertEq(ids.length, 2);
        assertEq(ids[0], 0);
        assertEq(ids[1], 1);
    }

    // --- claiming ---

    function testClaimTask() public {
        uint256 id = _postTask();
        vm.prank(worker);
        board.claimTask(id);
        (, address w,,,, AgentBoard.Status st,,,) = board.tasks(id);
        assertEq(w, worker);
        assertEq(uint8(st), uint8(AgentBoard.Status.Claimed));
    }

    function testClaimRequiresAgentId() public {
        uint256 id = _postTask();
        vm.prank(stranger);
        vm.expectRevert(AgentBoard.NotAgentIdHolder.selector);
        board.claimTask(id);
    }

    function testPosterCannotClaimOwn() public {
        uint256 id = _postTask();
        vm.prank(poster);
        vm.expectRevert(AgentBoard.SelfClaim.selector);
        board.claimTask(id);
    }

    function testDoubleClaimBlocked() public {
        uint256 id = _postTask();
        vm.prank(worker);
        board.claimTask(id);
        vm.prank(worker2);
        vm.expectRevert(AgentBoard.WrongStatus.selector);
        board.claimTask(id);
    }

    function testClaimAfterDeadlineReverts() public {
        uint256 id = _postTask();
        vm.warp(deadline + 1);
        vm.prank(worker);
        vm.expectRevert(AgentBoard.DeadlinePassed.selector);
        board.claimTask(id);
    }

    function testClaimNonexistentReverts() public {
        vm.prank(worker);
        vm.expectRevert(AgentBoard.TaskNotFound.selector);
        board.claimTask(99);
    }

    // --- submit / approve / reject ---

    function testFullLifecycle() public {
        uint256 id = _postTask();
        _postClaimSubmit(id);
        uint256 before = worker.balance;
        vm.prank(poster);
        board.approveWork(id);
        assertEq(worker.balance, before + REWARD);
        assertEq(address(board).balance, 0);
        assertEq(board.completedCount(worker), 1);
        assertEq(board.earnedTotal(worker), REWARD);
        (,,,,, AgentBoard.Status st,,,) = board.tasks(id);
        assertEq(uint8(st), uint8(AgentBoard.Status.Done));
    }

    function testSubmitOnlyWorker() public {
        uint256 id = _postTask();
        vm.prank(worker);
        board.claimTask(id);
        vm.prank(worker2);
        vm.expectRevert(AgentBoard.NotWorker.selector);
        board.submitWork(id, "proof");
    }

    function testSubmitAfterDeadlineReverts() public {
        uint256 id = _postTask();
        vm.prank(worker);
        board.claimTask(id);
        vm.warp(deadline + 1);
        vm.prank(worker);
        vm.expectRevert(AgentBoard.DeadlinePassed.selector);
        board.submitWork(id, "proof");
    }

    function testApproveOnlyPoster() public {
        uint256 id = _postTask();
        _postClaimSubmit(id);
        vm.prank(worker);
        vm.expectRevert(AgentBoard.NotPoster.selector);
        board.approveWork(id);
    }

    function testApproveBeforeSubmitReverts() public {
        uint256 id = _postTask();
        vm.prank(worker);
        board.claimTask(id);
        vm.prank(poster);
        vm.expectRevert(AgentBoard.WrongStatus.selector);
        board.approveWork(id);
    }

    function testRejectReopens() public {
        uint256 id = _postTask();
        _postClaimSubmit(id);
        vm.prank(poster);
        board.rejectWork(id);
        (address p, address w,,,, AgentBoard.Status st,,,) = board.tasks(id);
        assertEq(p, poster);
        assertEq(w, address(0));
        assertEq(uint8(st), uint8(AgentBoard.Status.Open));
        assertEq(address(board).balance, REWARD); // escrow still held
        // a different worker can now claim it
        vm.prank(worker2);
        board.claimTask(id);
    }

    function testDoubleApproveBlocked() public {
        uint256 id = _postTask();
        _postClaimSubmit(id);
        vm.prank(poster);
        board.approveWork(id);
        vm.prank(poster);
        vm.expectRevert(AgentBoard.WrongStatus.selector);
        board.approveWork(id);
    }

    // --- timeout ---

    function testClaimTimeout() public {
        uint256 id = _postTask();
        _postClaimSubmit(id);
        vm.warp(block.timestamp + 48 hours + 1);
        uint256 before = worker.balance;
        vm.prank(worker);
        board.claimTimeout(id);
        assertEq(worker.balance, before + REWARD);
        assertEq(board.completedCount(worker), 1);
        assertEq(board.earnedTotal(worker), REWARD);
        (,,,,, AgentBoard.Status st,,,) = board.tasks(id);
        assertEq(uint8(st), uint8(AgentBoard.Status.Done));
    }

    function testClaimTimeoutTooEarly() public {
        uint256 id = _postTask();
        _postClaimSubmit(id);
        vm.warp(block.timestamp + 47 hours);
        vm.prank(worker);
        vm.expectRevert(AgentBoard.TooEarly.selector);
        board.claimTimeout(id);
    }

    function testClaimTimeoutOnlyWorker() public {
        uint256 id = _postTask();
        _postClaimSubmit(id);
        vm.warp(block.timestamp + 49 hours);
        vm.prank(worker2);
        vm.expectRevert(AgentBoard.NotWorker.selector);
        board.claimTimeout(id);
    }

    // --- refund ---

    function testRefundUnclaimedAfterDeadline() public {
        uint256 id = _postTask();
        vm.warp(deadline + 1);
        uint256 before = poster.balance;
        vm.prank(poster);
        board.refundTask(id);
        assertEq(poster.balance, before + REWARD);
        assertEq(address(board).balance, 0);
        (,,,,, AgentBoard.Status st,,,) = board.tasks(id);
        assertEq(uint8(st), uint8(AgentBoard.Status.Refunded));
    }

    function testRefundClaimedButUnsubmittedAfterDeadline() public {
        uint256 id = _postTask();
        vm.prank(worker);
        board.claimTask(id);
        vm.warp(deadline + 1);
        uint256 before = poster.balance;
        vm.prank(poster);
        board.refundTask(id);
        assertEq(poster.balance, before + REWARD);
    }

    function testRefundBeforeDeadlineReverts() public {
        uint256 id = _postTask();
        vm.prank(poster);
        vm.expectRevert(AgentBoard.DeadlineNotPassed.selector);
        board.refundTask(id);
    }

    function testRefundOnlyPoster() public {
        uint256 id = _postTask();
        vm.warp(deadline + 1);
        vm.prank(worker);
        vm.expectRevert(AgentBoard.NotPoster.selector);
        board.refundTask(id);
    }

    function testRefundAfterSubmitReverts() public {
        uint256 id = _postTask();
        _postClaimSubmit(id);
        vm.warp(deadline + 1);
        vm.prank(poster);
        vm.expectRevert(AgentBoard.WrongStatus.selector);
        board.refundTask(id);
    }

    // --- reputation ---

    function testReputationViews() public {
        uint256 id1 = _postTask();
        _postClaimSubmit(id1);
        vm.prank(poster);
        board.approveWork(id1);

        uint256 id2 = _postTask();
        _postClaimSubmit(id2);
        vm.prank(poster);
        board.approveWork(id2);

        assertEq(board.completedCount(worker), 2);
        assertEq(board.earnedTotal(worker), 2 * REWARD);
        assertEq(board.completedCount(worker2), 0);
        assertEq(board.earnedTotal(worker2), 0);
    }

    // --- reentrancy ---

    function testReentrancyBlocked() public {
        ReentrantWorker attacker = new ReentrantWorker(board);
        agentId.mint(address(attacker));
        uint256 id = _postTask();
        vm.prank(address(attacker));
        board.claimTask(id);
        vm.prank(address(attacker));
        board.submitWork(id, "proof");
        attacker.setTask(id);
        vm.prank(poster);
        board.approveWork(id);
        // payout happened exactly once despite the re-entry attempt
        assertTrue(attacker.attacked());
        assertEq(address(attacker).balance, REWARD);
        assertEq(address(board).balance, 0);
        assertEq(board.completedCount(address(attacker)), 1);
    }

    function testDirectBnbTransferReverts() public {
        vm.prank(poster);
        (bool ok,) = address(board).call{value: 1 ether}("");
        assertFalse(ok);
        assertEq(address(board).balance, 0);
    }
}
