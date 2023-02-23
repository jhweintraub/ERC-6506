// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./TransparentIncentive.sol";
import "openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./lib/FixedPointMathLib.sol";
import "./TransparentIncentive.sol";

abstract contract OnChainVerifiable is TransparentIncentive, ReentrancyGuard {
    using SafeTransferLib for ERC20;

    function verifyVote(bytes32 incentive, bytes calldata voteInfo) public view returns (bool isVerifiable, bytes memory proofData) {
        IEscrowedGovIncentive.Incentive memory incentive = incentives[incentive];
        
        (isVerifiable, proofData) = IVoteVerifier(verifier).verifyVote(incentive.recipient, incentive.direction, incentive.proposalId, voteInfo);
    }

    //Dispute Mechanism
    function beginDispute(bytes32 incentiveId, bytes calldata disputeInfo) external payable noActiveDispute(incentiveId) {
        Incentive memory incentive = incentives[incentiveId];

        require(!disputes[incentiveId], "a dispute has already been initiated");
        require(incentive.deadline <= block.timestamp, "not enough time has passed yet to file a dispute");

        //Necesarry to prevent spam dispute filings
        require(msg.sender == incentive.incentivizer, "only the incentivizer can file a dispute over the incentive");

        //Transfer Bond to this
        ERC20(bondToken).safeTransferFrom(msg.sender, address(this), bondAmount);
        
        emit disputeInitiated(incentiveId, msg.sender, incentive.recipient);
    }

    function resolveDispute(bytes32 incentiveId, bytes calldata disputeResolutionInfo) external nonReentrant returns (bool isDismissed) {
        require(arbiters[msg.sender], "not allowed to resolve a dispute");
        require(disputes[incentiveId], "cannot resolve a dispute that has not been filed");

        Incentive memory incentive = incentives[incentiveId];

        (address winner) = abi.decode(disputeResolutionInfo, (address));
        require(winner == incentive.incentivizer || winner == incentive.recipient, "cannot resolve a dispute for a non-involved party");
        bool isDismissed = (winner == incentive.incentivizer);

        //Clean up the state
        delete disputes[incentiveId];
        delete incentives[incentiveId];

        //If the 
        if (isDismissed) {
            //Bond is kept by protocol and tokens given to the recipient
            ERC20(bondToken).safeTransfer(feeRecipient, bondAmount);
            ERC20(incentive.incentiveToken).safeTransfer(incentive.recipient, incentive.amount);
        } 
        else {
            //Return the bond and the tokens to the incentivizer
            ERC20(bondToken).safeTransfer(incentive.incentivizer, bondAmount);
            ERC20(incentive.incentiveToken).safeTransfer(incentive.incentivizer, incentive.amount);
        }

        emit disputeResolved(incentiveId, incentive.incentivizer, incentive.recipient, isDismissed);
    }
}