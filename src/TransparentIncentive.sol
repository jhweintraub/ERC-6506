// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./IncentiveBase.sol";

abstract contract TransparentIncentive is IncentiveBase {
    using SafeTransferLib for ERC20;

    //All transparent contracts can inherit this function. They would differ in the (re)claim functions.
    function incentivize(bytes32 incentiveId, bytes memory incentiveInfo) external virtual payable {
        (address incentiveToken,
        address recipient,
        uint amount,
        uint256 proposalId,
        bytes32 direction, //the keccack256 of the vote direction
        uint96 deadline) = abi.decode(incentiveInfo, (address, address, uint, uint256, bytes32, uint96));

        //TODO: Error Messages
        require(incentives[incentiveId].timestamp == 0, "Incentive already exists");
        require(recipient != address(0));
        require(incentiveToken != address(0));
        require(amount > 0);
        require(deadline > block.timestamp);

        //Make sure the committment is the same as the data they provided.
        bytes32 calculatedId = keccak256(incentiveInfo);
        require(calculatedId == incentiveId, "committment does not match underlying data");

        //Transfer the tokens to this (consider supporting Permit2 Library);
        ERC20(incentiveToken).safeTransferFrom(msg.sender, address(this), amount);

        //Create the new incentive object
        Incentive memory incentive;
        incentive.incentiveToken = incentiveToken;
        incentive.incentivizer = msg.sender;
        incentive.recipient = recipient;
        incentive.amount = amount;
        incentive.proposalId = proposalId;
        incentive.direction = direction;
        incentive.deadline = deadline;
        incentive.timestamp = uint96(block.timestamp); //this downcast is safe but maybe use a safeCast function

        //Place in storage and 
        incentives[incentiveId] = incentive;

        emit incentiveSent(msg.sender, incentiveToken, amount, recipient, incentiveInfo);
    }
}
