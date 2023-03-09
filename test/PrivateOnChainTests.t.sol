// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;


import "src/PrivateOnChainIncentive.sol";
import "src/OnChainVoteVerifier.sol";

import "src/interfaces/IEscrowedGovIncentive.sol";

import {MockGovernorBravo} from "src/mock/MockGovernorBravo.sol";
import {MockERC20Votes} from "src/mock/MockERC20Votes.sol";
import "openzeppelin/contracts/governance/TimelockController.sol";

import "../src/lib/SafeTransferLib.sol";
import "../src/lib/FixedPointMathLib.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract PrivateOnChainTests is Test {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    ERC20 USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    MockGovernorBravo governor;
    MockERC20Votes mockToken;
    
    TimelockController timelock;
    address[] addresses;

    PrivateOnChainIncentive provider;
    OnChainVoteVerifier verifier;

    address angel = address(1);
    address alice = address(2);
    address bob = address(3);
    address arbiter = address(4);

    address FEE_RECIPIENT = address(3);
    uint feeBP = 5e16; //5% of 1e18
    uint bondAmount = 50e6;// 50 USDC
    uint constant BASIS_POINTS = 1 ether;

    //The ID of our new fake governance proposal
    uint proposalId;

    event incentiveClaimed(address indexed incentivizer, address voter, bytes32 incentiveId, bytes proofData);
    event disputeInitiated(bytes32 indexed incentiveId, address indexed plaintiff, address indexed defendant);

    IEscrowedGovIncentive.Incentive incentive;

    constructor() {
        mockToken = new MockERC20Votes();

        addresses.push(address(this));
        timelock = new TimelockController(uint(0), addresses, addresses, address(this));
        
        governor = new MockGovernorBravo(mockToken, timelock);
        verifier = new OnChainVoteVerifier(address(governor));

        //Create the new incentive contract
        provider = new PrivateOnChainIncentive(
            FEE_RECIPIENT,
            address(verifier),
            feeBP,
            bondAmount,
            address(USDC));

        provider.addArbiter(arbiter);

        //Shit for debugging
        vm.label(address(provider), "provider");
        vm.label(address(USDC), "asset");
        vm.label(address(mockToken), "mockToken");
        vm.label(address(governor), "governor");
        vm.label(address(verifier), "verifier");

        vm.label(alice, "alice");
        vm.label(angel, "angel");

        startHoax(angel, angel);
        deal(address(USDC), angel, 1e12);
        USDC.approve(address(provider), type(uint).max);
        deal(address(mockToken), angel, 1e21);
        vm.stopPrank();

        startHoax(alice, alice);
        deal(address(USDC), angel, 1e12);
        USDC.approve(address(provider), type(uint).max);
        deal(address(mockToken), alice, 1e21);
        vm.stopPrank();
    }

    function setUp() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(USDC);
        //just call totalSupply. Doesn't matter what we call we just need it to be valid
        calldatas[0] = abi.encodeWithSelector(USDC.totalSupply.selector);
    
        //Create the proposal
        proposalId = governor.propose(targets, values, calldatas, "a fake proposal");
        vm.roll(block.number + 2);
    
    }

    function testCreateIncentive(uint amount) public returns (bytes32 incentiveId) {
        vm.assume(amount > 1e6 && amount < 1e12);

        bytes memory incentiveData = abi.encode(
            address(USDC),
            alice,
            angel,
            amount, //100 USDC
            proposalId,
            keccak256(abi.encodePacked(uint(1))),//1 = Yes
            block.timestamp + 1 weeks);

        // incentiveData = incentiveData ^ bytes("0xdeadbeef");

        //Unfortunately we cannot have the incentivize method return an id because in the private
        //situations you should already know it and have to commit to it ahead of time
        incentiveId = keccak256(incentiveData);
        
        //it literally doesn't matter what this data is since we already know the underlying committment value
        uint randomData = uint(incentiveId) ^ 0xdeadbeef;

        uint preBal = USDC.balanceOf(angel);

        incentive.incentivizer = angel;
        incentive.recipient = alice;
        incentive.incentiveToken = address(USDC);
        incentive.amount = amount;
        incentive.proposalId = proposalId;
        incentive.direction = keccak256(abi.encodePacked(uint(1)));
        incentive.deadline = uint96(block.timestamp) + 1 weeks;
        incentive.timestamp = uint96(block.timestamp);

        (address wallet,) = provider.predictDeterministic(incentive);

        startHoax(angel, angel);
        USDC.safeTransfer(wallet, amount);
        provider.incentivize(incentiveId, abi.encode(randomData));

        IEscrowedGovIncentive.Incentive memory incentive = provider.getIncentive(incentiveId);
        //Theoretically we only need to check that a single value made it into storage
        
        assertEq(incentive.incentivizer, angel, "incentivizer is not angel");
        assertEq(incentive.timestamp, uint96(block.timestamp), "block timestamps don't match");
        assertFalse(incentive.claimed, "claimed is true, it should be false");        

        assertEq(USDC.balanceOf(wallet), amount, "funds were not sent to wallet");
        assertEq(USDC.balanceOf(angel), preBal - amount, "funds were not deduced from angel");
        vm.stopPrank();
    }

    function testCannotClaimWithoutProperReveal(uint amount) public {
        vm.assume(amount > 1e6 && amount < 1e12);
        bytes32 incentiveId = testCreateIncentive(amount);

        startHoax(angel, angel);
        bytes memory incentiveData = abi.encode(
            address(USDC),
            alice,
            angel,
            amount + 1, //100 USDC
            proposalId,
            keccak256(abi.encodePacked(uint(1))),//1 = Yes
            block.timestamp + 1 weeks);

        vm.expectRevert("data provided does not match committment");
        provider.reclaimIncentive(incentiveId, incentiveData);
    }

    function testClaimIncentiveWithYesVote(uint amount) public {
        vm.assume(amount > 1e6 && amount < 1e12);
        //Submit the incentive
        bytes32 incentiveId = testCreateIncentive(amount);

        //Do the voting - Alice should vote for "YES"
        startHoax(alice, alice);
        governor.castVote(proposalId, uint8(1));

        uint preBal = USDC.balanceOf(alice);

        IGovernorCompatibilityBravo.Receipt memory receipt = governor.getReceipt(proposalId, alice);
        bytes memory proofData = abi.encode(receipt);

        bytes memory incentiveData = abi.encode(
            address(USDC),
            alice,
            angel,
            amount, //100 USDC
            proposalId,
            keccak256(abi.encodePacked(uint(1))),//1 = Yes
            block.timestamp + 1 weeks);

        provider.claimIncentive(incentiveId, incentiveData, payable(alice));
        
        uint expectedFeeAmount = amount.mulDivDown(feeBP, BASIS_POINTS);

        //Check that the fees were taken and the remaining was sent to alice
        assertEq(USDC.balanceOf(alice), preBal + (amount - expectedFeeAmount));
        assertEq(USDC.balanceOf(FEE_RECIPIENT), expectedFeeAmount);



        //Check that the state was managed correctly
        testProperReveal(incentiveId);
    }

    function testCannotClaimIncentiveWithNoVote(uint amount) public {
        vm.assume(amount > 1e6 && amount < 1e12);
        //Submit the incentive
        bytes32 incentiveId = testCreateIncentive(amount);

        //Do the voting - Alice should vote for "YES"
        startHoax(alice, alice);
        governor.castVote(proposalId, uint8(0));//Vote for 0 = "AGAINST"

        uint preBal = USDC.balanceOf(alice);

        bytes memory incentiveData = abi.encode(
            address(USDC),
            alice,
            angel,
            amount, //100 USDC
            proposalId,
            keccak256(abi.encodePacked(uint(1))),//1 = Yes
            block.timestamp + 1 weeks);

        //Make sure event logs are emitted correctly
        vm.expectRevert("Vote could not be verified");
        provider.claimIncentive(incentiveId, incentiveData, payable(alice));
    }

    function testClaimIncentiveWithAllowedClaimer(uint amount) public {
        vm.assume(amount > 1e6 && amount < 1e12);
        bytes32 incentiveId = testCreateIncentive(amount);

        //Do the voting - Alice should vote for "YES"
        startHoax(alice, alice);
        governor.castVote(proposalId, uint8(1));//Vote for 1 = "FOR"
        provider.modifyClaimer(bob, true);

        uint preBal = USDC.balanceOf(alice);

        vm.stopPrank();

        //Make sure event logs are emitted correctly
        hoax(bob, bob);

        bytes memory incentiveData = abi.encode(
            address(USDC),
            alice,
            angel,
            amount, //100 USDC
            proposalId,
            keccak256(abi.encodePacked(uint(1))),//1 = Yes
            block.timestamp + 1 weeks);

        provider.claimIncentive(incentiveId, incentiveData, payable(alice));

        vm.stopPrank();
        testProperReveal(incentiveId);
    }

    function testCannotClaimIncentiveWithoutAllowedClaimer(uint amount) public {
        vm.assume(amount > 1e6 && amount < 1e12);
        bytes32 incentiveId = testCreateIncentive(amount);

        //Do the voting - Alice should vote for "YES"
        startHoax(alice, alice);
        governor.castVote(proposalId, uint8(1));//Vote for 1 = "FOR"

        uint preBal = USDC.balanceOf(alice);

        vm.stopPrank();

        bytes memory incentiveData = abi.encode(
            address(USDC),
            alice,
            angel,
            amount, //100 USDC
            proposalId,
            keccak256(abi.encodePacked(uint(1))),//1 = Yes
            block.timestamp + 1 weeks);

        //Make sure event logs are emitted correctly
        hoax(bob, bob);
        
        vm.expectRevert("Not allowed to claim on behalf of recipient");
        provider.claimIncentive(incentiveId, incentiveData, payable(alice));

        vm.stopPrank();
    }

    function createDispute(uint amount) internal returns (bytes32 incentiveId) {
        incentiveId = testCreateIncentive(amount);

        uint96 currentTimestamp = uint96(block.timestamp);

        skip(2 weeks);

        uint preBal = USDC.balanceOf(angel);

        bytes memory incentiveData = abi.encode(
            address(USDC),
            alice,
            angel,
            amount, //100 USDC
            proposalId,
            keccak256(abi.encodePacked(uint(1))),//1 = Yes
            currentTimestamp + 1 weeks);

        hoax(angel, angel);
        provider.beginDispute(incentiveId, incentiveData);

        assert(provider.disputes(incentiveId));
        assertEq(USDC.balanceOf(angel), preBal - bondAmount, "Bond was not successfully payed");
    }

    function testDisputeForPlaintiff(uint amount) public {
        vm.assume(amount > 1e6 && amount < 1e12);
        
        uint preBal = USDC.balanceOf(angel);

        bytes32 incentiveId = createDispute(amount);

        hoax(arbiter, arbiter);
        provider.resolveDispute(incentiveId, abi.encode(angel));

        assertEq(USDC.balanceOf(angel), preBal, "tokens not returned to angel after dispute");
        testProperReveal(incentiveId);
    }

    function testDisputeForDefendant(uint amount) public {
        vm.assume(amount > 1e6 && amount < 1e12);
        
        uint preBal = USDC.balanceOf(alice);
        uint feeRecipientBal = USDC.balanceOf(FEE_RECIPIENT);

        bytes32 incentiveId = createDispute(amount);

        hoax(arbiter, arbiter);
        provider.resolveDispute(incentiveId, abi.encode(alice));

        assertEq(USDC.balanceOf(alice), preBal + amount);
        assertEq(USDC.balanceOf(FEE_RECIPIENT), feeRecipientBal + bondAmount);    

        testProperReveal(incentiveId);

    }

    function testProperReveal(bytes32 incentiveId) internal {
        IEscrowedGovIncentive.Incentive memory retrievedIncentive = provider.getIncentive(incentiveId);
        assertEq(retrievedIncentive.incentiveToken, address(USDC), "incentive tokens don't match");
        assertEq(retrievedIncentive.incentivizer, angel, "incentivizers don't match");
        assertEq(retrievedIncentive.recipient, alice, "recipients don't match");
        assertEq(retrievedIncentive.amount, incentive.amount, "amounts don't match");
        assertEq(retrievedIncentive.proposalId, incentive.proposalId, "proposalIds don't match");
        assertEq(retrievedIncentive.direction, keccak256(abi.encodePacked(uint(1))), "directions don't match");
        assertEq(retrievedIncentive.deadline, incentive.timestamp + 1 weeks, "deadlines don't match");
        assertEq(retrievedIncentive.timestamp, incentive.timestamp, "timestamps dont match");
        assert(retrievedIncentive.claimed);  
    }

}