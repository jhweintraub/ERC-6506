// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./TransparentIncentive.sol";
import "openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./lib/FixedPointMathLib.sol";
import "./SignatureVerifier.sol";
import "openzeppelin/contracts/access/Ownable.sol";

contract TransparentOffChainIncentives is TransparentIncentive, ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    address public immutable signatureVerifier;
    string public app;
    string public space;

    constructor(address _feeRecipient, address _verifier, uint _feeBP, uint _bondAmount, address _bondToken,
    address _signatureVerifier, string memory _app, string memory _space) 
    IncentiveBase(_feeRecipient, _verifier, _feeBP, _bondAmount, _bondToken) {
        signatureVerifier = _signatureVerifier;
        app = _app;
        space = _space;
    }


    //It should inherit from 

    function claimIncentive(bytes32 incentiveId, bytes memory reveal, address payable recipient) external nonReentrant noActiveDispute(incentiveId) isAllowedClaimer(incentiveId) {
        Incentive memory incentive = incentives[incentiveId];

        require(!incentive.claimed, "Incentive has already been claimed or clawed back");
        require(block.timestamp >= (incentive.deadline + 3 days), "not enough time has passed to claim yet");

        //Mark as claimed to prevent Reentry Attacks
        incentives[incentiveId].claimed = true;

        //Finally send the tokens to the address specified after calculating fee
        uint fee = incentive.amount.mulDivDown(feeBP, BASIS_POINTS);
        ERC20(incentive.incentiveToken).safeTransfer(feeRecipient, fee);
        ERC20(incentive.incentiveToken).safeTransfer(recipient, incentive.amount - fee);

        //There's no data needed for proof so emit the empty string
        emit incentiveClaimed(incentive.incentivizer, incentive.recipient, incentiveId, "");
    }

    function reclaimIncentive(bytes32 incentiveId, bytes memory reveal) noActiveDispute(incentiveId) external {
        Incentive memory incentive = incentives[incentiveId];

        require(msg.sender == incentive.incentivizer, "only incentivizer can reclaim funds");
        require(!incentive.claimed, "Incentive has already been claimed or clawed back");
        require(block.timestamp >= (incentive.deadline), "not enough time has passed to claim yet");
        require(block.timestamp <= (incentive.deadline + 3 days), "missed your window to reclaim");

    //     struct SingleChoiceVote {
    //     address from;
    //     string space;
    //     uint64 timestamp;
    //     bytes32 proposal;
    //     uint32 choice;
    //     string reason;
    //     string app;
    //     string metadata;
    // }
        (bool verified, bytes memory proofData) = verifyVote(incentiveId, reveal);
        require(verified, "Vote could not be verified");

        (uint64 timestamp, bytes32 proposal, uint32 choice, string memory reason,
        string memory metadata, bytes memory signature) = 
            abi.decode(reveal, (uint64, bytes32, uint32, string, string, bytes));

         //Mark as claimed to prevent Reentry Attacks
        incentives[incentiveId].claimed = true;
        
        //Send the incentive tokens back to the incentivizer
        ERC20(incentive.incentiveToken).safeTransfer(incentive.incentivizer, incentive.amount);
        emit incentiveReclaimed(incentive.incentivizer, incentive.recipient, incentive.incentiveToken, incentive.amount, signature);
    }

    function verifyVote(bytes32 _incentive, bytes memory voteInfo) public view returns (bool isVerifiable, bytes memory proofData) {
        Incentive memory incentive = incentives[_incentive];

        (uint64 timestamp, bytes32 proposal, uint32 choice, string memory reason,
        string memory metadata, bytes memory signature) = 
            abi.decode(voteInfo, (uint64, bytes32, uint32, string, string, bytes));

        //Need to use the abi.encode to keccack256 a uint
        require(keccak256(abi.encode(choice)) == incentive.direction, "vote does not match committment");
        require(uint(proposal) == incentive.proposalId, "Voted proposal must match commitment");

        SignatureVerifier.SingleChoiceVote memory vote = SignatureVerifier.SingleChoiceVote(
            incentive.recipient, space, timestamp, proposal, choice, reason, app, metadata
        );

        // console.logBytes(signature);
        // console.log("recipient: ", incentive.recipient);
        // console.log("space: ", space);
        // console.log("timestamp: ", timestamp);
        // console.logBytes32(proposal);
        // console.log("choice: ", choice);
        // console.log("reason: ", reason);
        // console.log("app: ", app);
        // console.log("metadata: ", metadata);
        // console.log("space: ", space);

        //Verify the signature
        return (SignatureVerifier(verifier).verifySingleChoiceSignature(vote, signature, incentive.recipient), signature);
    }

    //TODO: Reentrancy Guard all the functions
    //Dispute Mechanism
    function beginDispute(bytes32 incentiveId, bytes memory disputeInfo) external override payable {
        //Can just use inherited version since they would have reclaimed already if possible
        beginPublicDispute(incentiveId);
    }

    function resolveDispute(bytes32 incentiveId, bytes memory disputeResolutionInfo) external override returns(bool isDismissed) {
      return super.resolveOffChainDispute(incentiveId, disputeResolutionInfo);
    }

}
