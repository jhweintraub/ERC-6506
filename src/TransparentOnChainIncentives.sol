// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./TransparentIncentive.sol";
import "openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./lib/FixedPointMathLib.sol";

contract TransparentOnChainIncentives is TransparentIncentive, ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    constructor(address _feeRecipient, address _verifier, uint _feeBP, uint _bondAmount, address _bondToken) 
    IncentiveBase(_feeRecipient, _verifier, _feeBP, _bondAmount, _bondToken) {

    }

    function claimIncentive(bytes32 incentiveId, bytes calldata reveal, address payable recipient) external nonReentrant noActiveDispute(incentiveId) isAllowedClaimer(incentiveId) {
        incentive memory incentiveInfo = incentives[incentiveId];
        //You don't need to check that an incentive exists because if it doesn't then the verifyVote will fail and the amount will = 0

        //Reach out to vote oracle and verify that they did vote correctly
        (bool verified, bytes memory proofData) = verifyVote(incentiveId, reveal);
        require(verified, "Vote could not be verified");

        //Clean up the storage and prevent re-entrancy attacks through checks-effects interactions
        delete incentives[incentiveId];

        //Finally send the tokens to the address specified after calculating fee
        //Note: A claimer can steal all the tokens by specifying themselves as recipient, so it's up to the users to only specify a claimer they trust
        uint fee = incentiveInfo.amount.mulDivDown(feeBP, BASIS_POINTS);
        ERC20(incentiveInfo.incentiveToken).safeTransfer(feeRecipient, fee);
        ERC20(incentiveInfo.incentiveToken).safeTransfer(recipient, incentiveInfo.amount - fee);

        emit incentiveClaimed(incentiveInfo.incentivizer, incentiveInfo.recipient, incentiveId, proofData);
    }

    function reclaimIncentive(bytes32 incentiveId, bytes calldata reveal) noActiveDispute(incentiveId) external {
        incentive memory incentiveInfo = incentives[incentiveId];
        //You don't need to check that an incentive exists because if it doesn't then the verifyVote will fail and the amount will = 0

        (bool verified, bytes memory proofData) = verifyVote(incentiveId, reveal);
        require(!verified, "Cannot reclaim, user did vote in line with incentive");

        //Clean up the state for the gas refund
        delete incentives[incentiveId];
        
        //Send the incentive tokens back to the incentivizer
        ERC20(incentiveInfo.incentiveToken).safeTransfer(incentiveInfo.incentivizer, incentiveInfo.amount);
        emit incentiveReclaimed(incentiveInfo.incentivizer, incentiveInfo.recipient, incentiveInfo.incentiveToken, incentiveInfo.amount, reveal);
    }

    function verifyVote(bytes32 incentive, bytes calldata voteInfo) public view returns (bool isVerifiable, bytes memory proofData) {
        IEscrowedGovIncentive.incentive memory incentiveInfo = incentives[incentive];
        
        (isVerifiable, proofData) = IVoteVerifier(verifier).verifyVote(incentiveInfo.recipient, incentiveInfo.direction, incentiveInfo.proposalId, voteInfo);
    }


    //Dispute Mechanism
    function beginDispute(bytes32 incentiveId, bytes calldata disputeInfo) external payable {
        incentive memory incentiveInfo = incentives[incentiveId];

        require(!disputes[incentiveId], "a dispute has already been initiated");
        require(incentiveInfo.deadline <= block.timestamp, "not enough time has passed yet to file a dispute");

        //Necesarry to prevent spam dispute filings
        require(msg.sender == incentiveInfo.incentivizer, "only the incentivizer can file a dispute over the incentive");

        //Transfer Bond to this
        ERC20(bondToken).safeTransferFrom(msg.sender, address(this), bondAmount);
        
        emit disputeInitiated(incentiveId, msg.sender, incentiveInfo.recipient);


    }

    function resolveDispute(bytes32 incentiveId, bytes calldata disputeResolutionInfo) external nonReentrant returns (bool isDismissed) {
        require(arbiters[msg.sender], "not allowed to resolve a dispute");
        require(disputes[incentiveId], "cannot resolve a dispute that has not been filed");

        incentive memory incentiveInfo = incentives[incentiveId];

        (address winner) = abi.decode(disputeResolutionInfo, (address));
        require(winner == incentiveInfo.incentivizer || winner == incentiveInfo.recipient, "cannot resolve a dispute for a non-involved party");
        bool isDismissed = (winner == incentiveInfo.incentivizer);

        //Clean up the state
        delete disputes[incentiveId];
        delete incentives[incentiveId];

        //If the 
        if (isDismissed) {
            //Bond is kept by protocol and tokens given to the recipient
            ERC20(bondToken).safeTransfer(feeRecipient, bondAmount);
            ERC20(incentiveInfo.incentiveToken).safeTransfer(incentiveInfo.recipient, incentiveInfo.amount);
        } 
        else {
            //Return the bond and the tokens to the incentivizer
            ERC20(bondToken).safeTransfer(incentiveInfo.incentivizer, bondAmount);
            ERC20(incentiveInfo.incentiveToken).safeTransfer(incentiveInfo.incentivizer, incentiveInfo.amount);
        }

        emit disputeResolved(incentiveId, incentiveInfo.incentivizer, incentiveInfo.recipient, isDismissed);
    }


}
