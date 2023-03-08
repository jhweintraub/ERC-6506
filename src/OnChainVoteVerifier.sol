// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "openzeppelin/contracts/governance/compatibility/IGovernorCompatibilityBravo.sol";
import "./interfaces/IVoteVerifier.sol";

contract OnChainVoteVerifier is IVoteVerifier {

    IGovernorCompatibilityBravo public immutable votingContract;

    constructor(address _votingContract) {
        votingContract = IGovernorCompatibilityBravo(_votingContract);
    }

    function verifyVote(IEscrowedGovIncentive.Incentive calldata incentive, bytes calldata voteData) external view returns (bool, bytes memory) {
        
        //You don't need to check anything else about the vote like that it's ended since your vote can't be changed once made
        //So you can literally claim your incentive immediately after voting if verification is on-chain.
        
        IGovernorCompatibilityBravo.Receipt memory receipt = votingContract.getReceipt(incentive.proposalId, incentive.recipient);

        bytes32 direction = keccak256(abi.encode(receipt.support));//get the direction hash

        console.log("receipt: ", receipt.support);

        //The hash is only really used over int to handle different voting systems counting votes with different types
        //This way if a governance system uses a uint,bool, string, bytes, etc. it can still be counted without needing to redefine the entire struct
        
        //Return if the vote found was the direction committed to, and the 
        console.log("voted direction: ", uint(direction));
        console.log("incentive direction: ", uint(incentive.direction));
        return (direction == incentive.direction, abi.encode(receipt));

    }

}