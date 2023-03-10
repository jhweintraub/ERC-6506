// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;


import "src/TransparentOffChainIncentive.sol";
import "src/SignatureVerifier.sol";

import "src/interfaces/IEscrowedGovIncentive.sol";
import "src/lib/MerkleTreeGenerator.sol";

import "openzeppelin/contracts/utils/cryptography/MerkleProof.sol";


import "../src/lib/SafeTransferLib.sol";
import "../src/lib/FixedPointMathLib.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract TransparentOffChainTests is Test {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    ERC20 USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    
    address[] addresses;

    TransparentOffChainIncentives provider;
    SignatureVerifier verifier;

    address angel = address(1);
    address alice = 0x070341aA5Ed571f0FB2c4a5641409B1A46b4961b;
    address bob = address(3);
    address arbiter = address(4);

    address FEE_RECIPIENT = address(3);
    uint feeBP = 5e16; //5% of 1e18
    uint bondAmount = 50e6;// 50 USDC
    uint constant BASIS_POINTS = 1 ether;

    //The ID of our new fake governance proposal

    event incentiveClaimed(address indexed incentivizer, address voter, bytes32 incentiveId, bytes proofData);
    event disputeInitiated(bytes32 indexed incentiveId, address indexed plaintiff, address indexed defendant);

    bytes32 proposalId = 0x15a031fa5f848aac269214a7cda2fed314590ab0c935b6879e4bf7fb9d87cc2c;
    string metadata = "{}";
    uint32 choice = 1;
    string reason = "";
    uint64 timestamp = 1677271449;
    bytes signature = hex"ba87e5918ea6c7e0e3301d149ac9263e30e3e46aee545e1cc49240edf8f402777d6642d1f3db11a34539073199bf8767af24223e1c28dd4f50b4cbf4daa30df21c";
    string space = "aave.eth";
    string app = "snapshot";

    bytes32 MerkleRoot;
    bytes32[] voters;

    constructor() {
        verifier = new SignatureVerifier();

        //Create the new incentive contract
        provider = new TransparentOffChainIncentives(
            FEE_RECIPIENT,
            address(verifier),
            feeBP,
            bondAmount,
            address(USDC),
            address(verifier),
            app,
            space
            );

        provider.addArbiter(arbiter);

        //Shit for debugging
        vm.label(address(provider), "provider");
        vm.label(address(USDC), "asset");
        vm.label(address(verifier), "verifier");

        vm.label(alice, "alice");
        vm.label(angel, "angel");

        startHoax(angel, angel);
        deal(address(USDC), angel, 1e12);
        USDC.approve(address(provider), type(uint).max);
        vm.stopPrank();

        startHoax(alice, alice);
        deal(address(USDC), alice, 1e12);
        USDC.approve(address(provider), type(uint).max);
        vm.stopPrank();
    }

    function setUp() public {
        for(uint x = 0; x < 9; x++) {
            voters.push(keccak256(abi.encode(x)));
        }

        voters.push(keccak256(abi.encode(alice)));
        MerkleRoot = MerkleTreeGenerator.getRoot(voters);
    }

    function testCreateIncentive(uint amount) public returns (bytes32 incentiveId) {
        vm.assume(amount > 1e6 && amount < 1e12);

        bytes memory incentiveData = abi.encode(
            address(USDC),
            alice,
            amount, //100 USDC
            proposalId,
            keccak256(abi.encodePacked(uint(0))),//1 = Yes
            block.timestamp + 1 weeks
        );

        //Unfortunately we cannot have the incentivize method return an id because in the private
        //situations you should already know it and have to commit to it ahead of time
        incentiveId = keccak256(incentiveData);
        
        uint preBal = USDC.balanceOf(angel);

        hoax(angel, angel);
        provider.incentivize(bytes32(""), incentiveData);

        IEscrowedGovIncentive.Incentive memory incentive = provider.getIncentive(incentiveId);

        //Theoretically we only need to check that a single value made it into storage
        
        assertEq(incentive.incentiveToken, address(USDC));
        assertEq(incentive.incentivizer, angel);
        assertEq(incentive.recipient, alice);
        assertEq(incentive.amount, amount);
        assertEq(incentive.proposalId, uint(proposalId));
        assertEq(incentive.direction, keccak256(abi.encodePacked(uint(0))));
        assertEq(incentive.deadline, block.timestamp + 1 weeks);
        assertEq(incentive.timestamp, uint96(block.timestamp));
        assertFalse(incentive.claimed);        

        assertEq(USDC.balanceOf(angel), preBal - amount);
        assertEq(USDC.balanceOf(address(provider)), amount);
    }

    function testClaimIncentiveWithYesVote(uint amount) public {
        vm.assume(amount > 1e6 && amount < 1e12);
        //Submit the incentive
        bytes32 incentiveId = testCreateIncentive(amount);

        startHoax(alice, alice);

        //Skip to a time after the deadline but before end of reclamation window
        skip(1 weeks);
        vm.expectRevert("not enough time has passed to claim yet");
        provider.claimIncentive(incentiveId, "", payable(alice));

        //Skip to some time after the deadline 
        
        skip(7 days);
        uint preBal = USDC.balanceOf(alice);

        //TODO: Fix
        //Make sure event logs are emitted correctly
        // vm.expectEmit(true, true, true, true);
        // emit incentiveClaimed(angel, alice, incentiveId, proofData);

        provider.claimIncentive(incentiveId, "", payable(alice));
        
        uint expectedFeeAmount = amount.mulDivDown(feeBP, BASIS_POINTS);

        //Check that the fees were taken and the remaining was sent to alice
        assertEq(USDC.balanceOf(alice), preBal + (amount - expectedFeeAmount));
        assertEq(USDC.balanceOf(FEE_RECIPIENT), expectedFeeAmount);

        //Check that the state was managed correctly
        IEscrowedGovIncentive.Incentive memory incentive = provider.getIncentive(incentiveId);
        assert(incentive.claimed);
    }

    function testReclaimIncentiveWithNoVote(uint amount) public {
        vm.assume(amount > 1e6 && amount < 1e12);

        uint preBal = USDC.balanceOf(angel);

        //Submit the incentive
        bytes32 incentiveId = testCreateIncentive(amount);

        bytes memory correctVoteInfo = abi.encode(
            timestamp,
            proposalId,
            choice,
            reason,
            metadata,
            signature
        );

        //This one has an incorrect timestamp so the signature won't match the data
        bytes memory incorrectVoteInfo = abi.encode(
            timestamp+1,
            proposalId,
            choice,
            reason,
            metadata,
            signature
        );

        startHoax(angel, angel);

        //TODO: expectRevert because window hasn't closed yet
        vm.expectRevert("not enough time has passed to claim yet");
        provider.reclaimIncentive(incentiveId, correctVoteInfo);

        //Skip forward to end of voting window
        skip(2 weeks);
        vm.expectRevert("missed your window to reclaim");
        provider.reclaimIncentive(incentiveId, correctVoteInfo);

        //Go back 1 week to the beginning of the claiming window
        rewind(1 weeks);

        console.log("preparing to revert");
        //Cannot claim with invalid signature
        vm.expectRevert("Vote could not be verified");
        provider.reclaimIncentive(incentiveId, incorrectVoteInfo);

        console.log("GOT HERE");

        //Cannot claim with invalid signature
        provider.reclaimIncentive(incentiveId, correctVoteInfo);


        assertEq(USDC.balanceOf(angel), preBal, "incentive not returned to angel");
        IEscrowedGovIncentive.Incentive memory incentive = provider.getIncentive(incentiveId);
        assert(incentive.claimed);

        vm.stopPrank();

        //Alice should not be able to claim since it was already clawed back
        hoax(alice, alice);
        vm.expectRevert("Incentive has already been claimed or clawed back");
        provider.claimIncentive(incentiveId, "", payable(alice));
    }


    function testClaimIncentiveWithAllowedClaimer(uint amount) public {
        vm.assume(amount > 1e6 && amount < 1e12);
        bytes32 incentiveId = testCreateIncentive(amount);

        //Do the voting - Alice should vote for "YES"
        startHoax(alice, alice);
        //TODO: Create Signature

        provider.modifyClaimer(bob, true);

        uint preBal = USDC.balanceOf(alice);

        vm.stopPrank();
        skip(10 days);

        //Make sure event logs are emitted correctly
        hoax(bob, bob);
        provider.claimIncentive(incentiveId, "", payable(alice));

        vm.stopPrank();
    }

    function testCannotClaimIncentiveWithoutAllowedClaimer(uint amount) public {
        vm.assume(amount > 1e6 && amount < 1e12);
        bytes32 incentiveId = testCreateIncentive(amount);

        //Do the voting - Alice should vote for "YES"
        startHoax(alice, alice);
        //TODO: Create Signature

        uint preBal = USDC.balanceOf(alice);

        vm.stopPrank();

        //Make sure event logs are emitted correctly
        hoax(bob, bob);
        skip(10 days);
        
        vm.expectRevert("Not allowed to claim on behalf of recipient");
        provider.claimIncentive(incentiveId, "", payable(alice));

        vm.stopPrank();
    }

    function createDispute(uint amount) internal returns (bytes32 incentiveId) {
        incentiveId = testCreateIncentive(amount);

        skip(1 weeks);

        uint preBal = USDC.balanceOf(angel);

        //TODO: Expect Revert due to window not closing
        //Roll forward to dispute window open 

        hoax(angel, angel);
        provider.beginDispute(incentiveId, "");

        assert(provider.disputes(incentiveId));
        assertEq(USDC.balanceOf(angel), preBal - bondAmount, "Bond was not successfully payed");
    
        //TODO: Create Merkle Root for Voters
        //TODO: Add Merkle Root
        hoax(arbiter, arbiter);
        provider.setMerkleRoot(incentiveId, MerkleRoot);
    
    }

    function testDisputeForPlaintiff(uint amount) public {
        vm.assume(amount > 1e6 && amount < 1e12);
        
        uint preBal = USDC.balanceOf(angel);

        bytes32 incentiveId = createDispute(amount);

        //TODO: vm.expectRevert from window not closing
        //TODO: Fast forward then claim
        skip(3 days);

        hoax(angel, angel);
        provider.resolveDispute(incentiveId, abi.encode(angel));

        assertEq(USDC.balanceOf(angel), preBal);
        IEscrowedGovIncentive.Incentive memory incentive = provider.getIncentive(incentiveId);
        assert(incentive.claimed);
    }

    function testDisputeForDefendant(uint amount) public {
        vm.assume(amount > 1e6 && amount < 1e12);
        
        uint preBal = USDC.balanceOf(alice);
        uint feeRecipientBal = USDC.balanceOf(FEE_RECIPIENT);

        bytes32 incentiveId = createDispute(amount);


        //TODO: Create merkle proof and verify
        bytes32[] memory merkleProof = MerkleTreeGenerator.getProof(voters, 9);

        hoax(alice, alice);
        provider.resolveDispute(incentiveId, abi.encode(merkleProof));
        

        assertEq(USDC.balanceOf(alice), preBal + amount);
        assertEq(USDC.balanceOf(FEE_RECIPIENT), feeRecipientBal + bondAmount);    

        IEscrowedGovIncentive.Incentive memory incentive = provider.getIncentive(incentiveId);
        assert(incentive.claimed);
    }

}