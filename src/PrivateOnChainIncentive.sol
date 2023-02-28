// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./TransparentIncentive.sol";
import "openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./lib/FixedPointMathLib.sol";
import "./PrivateIncentive.sol";
import "forge-std/console.sol";

contract PrivateOnChainIncentives is PrivateIncentive, ReentrancyGuard  {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    constructor(address _feeRecipient, address _verifier, uint _feeBP, uint _bondAmount, address _bondToken) 
    PrivateIncentive(_feeRecipient, _verifier, _feeBP, _bondAmount, _bondToken) {

    }

    function claimIncentive(bytes32 incentiveId, bytes calldata reveal, address payable recipient) external nonReentrant noActiveDispute(incentiveId) isAllowedClaimer(incentiveId) {
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

    function reclaimIncentive(bytes32 incentiveId, bytes calldata reveal) noActiveDispute(incentiveId) external {
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
        emit incentiveReclaimed(incentive.incentivizer, incentive.recipient, incentive.incentiveToken, incentive.amount, reveal);
    }

    function validateReveal(bytes32 incentiveId, bytes calldata reveal) internal returns (Incentive memory) {
        (address incentiveToken,
        address recipient,
        address incentivizer,
        uint amount,
        uint256 proposalId,
        bytes32 direction, //the keccack256 of the vote direction
        uint96 deadline) = abi.decode(reveal, (address, address, address, uint, uint256, bytes32, uint96));

        bytes32 revealHash = keccak256(reveal);
        require(revealHash == incentiveId, "data provided does not match committment");

        //Verify that they revealed the info for an already committed-to incentive.        
        Incentive storage incentive = incentives[revealHash];
        require(incentive.timestamp > 0, "no incentive exists for provided data");

        //Store the revealed data in long-term storage
        incentive.incentiveToken = incentiveToken;
        incentive.amount = amount;
        incentive.incentivizer = incentivizer;
        incentive.proposalId = proposalId;
        incentive.direction = direction;
        incentive.deadline = deadline;

        return incentive;
    }

    //TODO: Reentrancy Guard all the functions
    //Dispute Mechanism
    function beginDispute(bytes32 incentiveId, bytes calldata disputeInfo) external override payable {
        //Make sure the reveal matches, and if so then begin to file dispute
        validateReveal(incentiveId, disputeInfo);

        this.beginPublicDispute(incentiveId);
    }

    function resolveDispute(bytes32 incentiveId, bytes calldata disputeResolutionInfo) external override returns (bool isDismissed) {
        return resolveOnChainDispute(incentiveId, disputeResolutionInfo);
    }

}