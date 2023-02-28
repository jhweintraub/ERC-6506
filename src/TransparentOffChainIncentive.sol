// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./TransparentIncentive.sol";
import "openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./lib/FixedPointMathLib.sol";

contract TransparentOffChainIncentives is TransparentIncentive, ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    constructor(address _feeRecipient, address _verifier, uint _feeBP, uint _bondAmount, address _bondToken) 
    IncentiveBase(_feeRecipient, _verifier, _feeBP, _bondAmount, _bondToken) {

    }


    //It should inherit from 

    function claimIncentive(bytes32 incentiveId, bytes calldata reveal, address payable recipient) external nonReentrant noActiveDispute(incentiveId) isAllowedClaimer(incentiveId) {
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

    function reclaimIncentive(bytes32 incentiveId, bytes calldata reveal) noActiveDispute(incentiveId) external {
        Incentive memory incentive = incentives[incentiveId];

        require(msg.sender == incentive.incentivizer, "only incentivizer can reclaim funds");
        require(!incentive.claimed, "Incentive has already been claimed or clawed back");
        require(block.timestamp >= (incentive.deadline), "not enough time has passed to claim yet");

        //TODO: Parse the reveal
        //compare the signature
        //get the info

        //reclaim the incentive
    }

        //TODO: Reentrancy Guard all the functions
    //Dispute Mechanism
    function beginDispute(bytes32 incentiveId, bytes calldata disputeInfo) external override payable {
        //TODO: 

        //Can just use inherited version since they would reclaim if possible
        this.beginPublicDispute(incentiveId);
    }

    function resolveDispute(bytes32 incentiveId, bytes calldata disputeResolutionInfo) external override returns(bool isDismissed) {
      
      return super.resolveOffChainDispute(incentiveId, disputeResolutionInfo);
    }


}
