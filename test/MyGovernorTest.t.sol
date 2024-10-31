// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {Box} from "../src/Box.sol";
import {GovToken} from "../src/GovToken.sol";
import {TimeLock} from "../src/TimeLock.sol";

contract MyGovernorTest is Test {
    MyGovernor governor;
    Box box;
    GovToken govToken;
    TimeLock timelock;

    address public USER = makeAddr("user");
    address public ANTI_USER = makeAddr("anti");
    address public FOR_USER = makeAddr("for");
    
    uint256 public constant INITIAL_SUPPLY = 100 ether;

    uint256 public constant MIN_DELAY = 3600;
    uint256 public constant VOTING_DELAY = 1;
    uint256 public constant VOTING_PERIOD = 50400;

    address[] proposers;
    address[] executers;
    uint256[] values;
    bytes[] calldatas;
    address[] targets;


    function setUp() public {
        govToken = new GovToken();
        govToken.mint(USER, INITIAL_SUPPLY / 3);
        govToken.mint(ANTI_USER, INITIAL_SUPPLY / 3);
        govToken.mint(FOR_USER, INITIAL_SUPPLY / 3);

        vm.startPrank(ANTI_USER);
        govToken.delegate(ANTI_USER);
        vm.stopPrank();

        vm.startPrank(FOR_USER);
        govToken.delegate(FOR_USER);
        vm.stopPrank();

        vm.startPrank(USER);
        govToken.delegate(USER);
   
        timelock = new TimeLock(MIN_DELAY, proposers, executers);
        governor = new MyGovernor(govToken, timelock);

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();

        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(executorRole, address(0));
        timelock.grantRole(adminRole, USER);
        vm.stopPrank();
   

        box = new Box();
        box.transferOwnership(address(timelock));
    }

    function testCantUpdateBoxWithoutGovernance() public {
        vm.expectRevert();
        box.store(1);
    }

    function testGovernanceUpdatesBox() public {
        uint256 valueToStore = 42;
        string memory description = "store 42 in Box";
        bytes memory encodedFunctionCall = abi.encodeWithSignature("store(uint256)", valueToStore);

        values.push(0);
        calldatas.push(encodedFunctionCall);
        targets.push(address(box));
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        console.log("Proposal state: ", uint256(governor.state(proposalId)));

        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY + 1);
        console.log("Proposal state: ", uint256(governor.state(proposalId)));

        string memory reason = "something";
        uint8 voteYay = 1; 
        uint8 voteNay = 0; 

        vm.prank(USER);
        governor.castVoteWithReason(proposalId, voteYay, reason);

        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + MIN_DELAY + 1);

        vm.prank(ANTI_USER);
        governor.castVoteWithReason(proposalId, voteNay, reason);

        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + MIN_DELAY + 1);
        
        vm.prank(FOR_USER);
        governor.castVoteWithReason(proposalId, voteYay, reason);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);


        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + MIN_DELAY + 1);

        governor.execute(targets, values, calldatas, descriptionHash);

        assertEq(box.getNumber(), valueToStore);
        console.log(box.getNumber());
    }
}
