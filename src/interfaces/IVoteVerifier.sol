// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;

interface IVoteVerifier {

    function verifyVote(address voter, bytes32 vote, uint proposalId, bytes calldata voteData) external view returns (bool, bytes memory);

    //TODO: Determine is getVote() should return uint or bytes32 or bytes
}