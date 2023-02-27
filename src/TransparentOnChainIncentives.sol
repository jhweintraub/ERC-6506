// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./TransparentIncentive.sol";
import "openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./lib/FixedPointMathLib.sol";
import "./OnChainVerifiable.sol";

contract TransparentOnChainIncentives is TransparentIncentive, OnChainVerifiable {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    constructor(address _feeRecipient, address _verifier, uint _feeBP, uint _bondAmount, address _bondToken) 
    IncentiveBase(_feeRecipient, _verifier, _feeBP, _bondAmount, _bondToken) {

    }

    function claimIncentive(bytes32 incentiveId, bytes calldata reveal, address payable recipient) external nonReentrant noActiveDispute(incentiveId) isAllowedClaimer(incentiveId) {
        Incentive memory incentive = incentives[incentiveId];
        require(!incentive.claimed, "Incentive has already been reclaimed");

        //You don't need to check that an incentive exists because if it doesn't then the verifyVote will fail and the amount will = 0

        //Reach out to vote oracle and verify that they did vote correctly
        (bool verified, bytes memory proofData) = verifyVote(incentiveId, reveal);
        require(verified, "Vote could not be verified");

        //Mark as claimed to prevent Reentry Attacks
        incentives[incentiveId].claimed = true;

        //Finally send the tokens to the address specified after calculating fee
        //Note: A claimer can steal all the tokens by specifying themselves as recipient, so it's up to the users to only specify a claimer they trust
        uint fee = incentive.amount.mulDivDown(feeBP, BASIS_POINTS);
        ERC20(incentive.incentiveToken).safeTransfer(feeRecipient, fee);
        ERC20(incentive.incentiveToken).safeTransfer(recipient, incentive.amount - fee);

        emit incentiveClaimed(incentive.incentivizer, incentive.recipient, incentiveId, proofData);
    }

    function reclaimIncentive(bytes32 incentiveId, bytes calldata reveal) noActiveDispute(incentiveId) external {
        Incentive memory incentive = incentives[incentiveId];
        require(!incentive.claimed, "Incentive has already been reclaimed");
        
        (bool verified, bytes memory proofData) = verifyVote(incentiveId, reveal);
        require(!verified, "Cannot reclaim, user did vote in line with incentive");

        //Mark as claimed to prevent Reentry Attacks
        incentives[incentiveId].claimed = true;
        
        //Send the incentive tokens back to the incentivizer
        ERC20(incentive.incentiveToken).safeTransfer(incentive.incentivizer, incentive.amount);
        emit incentiveReclaimed(incentive.incentivizer, incentive.recipient, incentive.incentiveToken, incentive.amount, reveal);
    }


}
