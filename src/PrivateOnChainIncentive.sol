// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./TransparentIncentive.sol";
import "openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./lib/FixedPointMathLib.sol";
import "./PrivateIncentive.sol";
import "./OnChainVoteVerifier.sol";
import "forge-std/console.sol";

contract PrivateOnChainIncentive is PrivateIncentive, ReentrancyGuard  {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    constructor(address _feeRecipient, address _verifier, uint _feeBP, uint _bondAmount, address _bondToken) 
    PrivateIncentive(_feeRecipient, _verifier, _feeBP, _bondAmount, _bondToken) {

    }

    function claimIncentive(bytes32 incentiveId, bytes memory reveal, address payable recipient) external nonReentrant noActiveDispute(incentiveId) isAllowedClaimer(incentiveId) {
        Incentive memory incentive = validateReveal(incentiveId, reveal);

        //Reach out to vote oracle and verify that they did vote correctly
        (bool verified, bytes memory proofData) = verifyVote(incentiveId, reveal);
        require(verified, "Vote could not be verified");

        //Prevent re-entrancy attacks through checks-effects interactions
        incentives[incentiveId].claimed = true;

        //TODO: Fix later --- This is not the most gas efficient way to do this but it works
        
        //Finally retrieve the tokens from the smart wallet and send to the address specified after calculating fee
        retrieveTokens(incentive);
        
        uint fee = incentive.amount.mulDivDown(feeBP, BASIS_POINTS);
        ERC20(incentive.incentiveToken).safeTransfer(feeRecipient, fee);
        ERC20(incentive.incentiveToken).safeTransfer(recipient, incentive.amount - fee);

        emit incentiveClaimed(incentive.incentivizer, incentive.recipient, incentiveId, proofData);
    }

    function reclaimIncentive(bytes32 incentiveId, bytes memory reveal) nonReentrant noActiveDispute(incentiveId) external {
        Incentive memory incentive = validateReveal(incentiveId, reveal);
        
        // Incentive memory incentive = incentives[incentiveId];
        require(!incentive.claimed, "Incentive has already been reclaimed");

        (bool verified, bytes memory proofData) = verifyVote(incentiveId, reveal);
        require(!verified, "Cannot reclaim, user did vote in line with incentive");

        //Mark as claimed to prevent Reentry Attacks
        incentives[incentiveId].claimed = true;

        //Retrieve the incentive tokens and send back to the incentivizer
        retrieveTokens(incentive);
        ERC20(incentive.incentiveToken).safeTransfer(incentive.incentivizer, incentive.amount);
        emit incentiveReclaimed(incentive.incentivizer, incentive.recipient, incentive.incentiveToken, incentive.amount, proofData);
    }


    //TODO: Reentrancy Guard all the functions
    //Dispute Mechanism
    function beginDispute(bytes32 incentiveId, bytes memory disputeInfo) external override payable {
        //Make sure the reveal matches, and if so then begin to file dispute
        validateReveal(incentiveId, disputeInfo);

        beginPublicDispute(incentiveId);
    }

    function verifyVote(bytes32 _incentive, bytes memory voteInfo) public view returns (bool isVerifiable, bytes memory proofData) {
        IEscrowedGovIncentive.Incentive memory incentive = incentives[_incentive];

        return OnChainVoteVerifier(verifier).verifyVote(incentive, voteInfo);
        
    }

    function resolveDispute(bytes32 incentiveId, bytes memory disputeResolutionInfo) external override nonReentrant returns (bool isDismissed) {
        //Just let the fucking arbiters handle it not like this dispute would ever get filed anyways
        Incentive memory incentive = incentives[incentiveId];
        retrieveTokens(incentive);//need to get the tokens from the smart wallet before we finish the dispute and send it off

        return resolveOnChainDispute(incentiveId, disputeResolutionInfo);
    }

}