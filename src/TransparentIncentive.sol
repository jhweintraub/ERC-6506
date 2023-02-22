// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./IncentiveBase.sol";

abstract contract TransparentIncentive is IncentiveBase {
    using SafeTransferLib for ERC20;

    mapping(bytes32 => bool) public disputes;

    //All transparent contracts can inherit this function. They would differ in the (re)claim functions.
    function incentivize(bytes32 incentiveId, bytes calldata incentiveInfo) external payable {
        (address incentiveToken,
        address recipient,
        uint amount,
        uint256 proposalId,
        bytes32 direction, //the keccack256 of the vote direction
        uint96 deadline,
        uint64 nonce) = abi.decode(incentiveInfo, (address, address, uint, uint256, bytes32, uint96, uint64));

        //TODO: Error Messages
        require(incentives[incentiveId].timestamp == 0, "Incentive already exists");
        require(recipient != address(0));
        require(incentiveToken != address(0));
        require(amount > 0);
        require(deadline > block.timestamp);
        require(nonce > nonces[msg.sender]);

        //Transfer the tokens to this (consider supporting Permit2 Library);
        ERC20(incentiveToken).safeTransferFrom(msg.sender, address(this), amount);

        //Make sure the committment is the same as the data they provided.
        bytes32 calculatedId = keccak256(abi.encode(incentiveInfo, msg.sender, block.timestamp));
        require(calculatedId == incentiveId);

        //Create the new incentive object
        incentive memory newIncentive;
        newIncentive.incentiveToken = incentiveToken;
        newIncentive.incentivizer = msg.sender;
        newIncentive.recipient = recipient;
        newIncentive.amount = amount;
        newIncentive.proposalId = proposalId;
        newIncentive.direction = direction;
        newIncentive.deadline = deadline;
        newIncentive.timestamp = uint96(block.timestamp); //this downcast is safe
        newIncentive.nonce = nonce;

        //Place in storage and 
        incentives[incentiveId] = newIncentive;
        nonces[msg.sender] = nonce;

        emit incentiveSent(msg.sender, incentiveToken, amount, recipient, incentiveInfo);
    }

    modifier isAllowedClaimer(bytes32 incentiveId) {
        incentive memory incentiveInfo = incentives[incentiveId];

        if (msg.sender != incentiveInfo.recipient) {
            require(allowedClaimers[incentiveInfo.recipient][msg.sender], "Not allowed to claim on behalf of recipient");
        }  
        _;
    }

    modifier noActiveDispute(bytes32 incentiveId) {
        require(!disputes[incentiveId], "Cannot proceed while dispute is being processed");
        _;
    }
  
}
