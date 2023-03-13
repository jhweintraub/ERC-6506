// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;

interface IEscrowedGovIncentive {
    struct Incentive {
      address incentiveToken;
      address incentivizer;
      address recipient;
      uint amount;
      uint256 proposalId;
      bytes32 direction; //the keccack256 of the vote direction
      uint96 deadline;
      uint96 timestamp;
      bool claimed;
  }

  event incentiveSent(address indexed incentivizer, address indexed token, uint256 indexed amount, address recipient, bytes data);
  event incentiveReclaimed(address incentivizer, address indexed recipient, address indexed token, uint256 indexed amount, bytes data);
  event modifiedClaimer(address recipient, address claimer, bool direction);
  event incentiveClaimed(address indexed incentivizer, address voter, bytes32 incentiveId, bytes proofData);
  event disputeInitiated(bytes32 indexed incentiveId, address indexed plaintiff, address indexed defendant);
  event disputeResolved(bytes32 indexed incentive, address indexed plaintiff, address indexed defendant, bool dismissed);

  //Core mechanism
  function incentivize(bytes32 incentiveId, bytes memory incentiveInfo) external payable;

  function claimIncentive(bytes32 incentiveId, bytes memory reveal, address payable recipient) external;
  
  function reclaimIncentive(bytes32 incentiveId, bytes memory reveal) external;
  
  function verifyVote(bytes32 incentive, bytes memory voteInfo) external view returns (bool isVerifiable, bytes memory proofData);

  function modifyClaimer(address claimer, bool designation) external;

  //Dispute Mechanism
  function beginDispute(bytes32 incentiveId, bytes memory disputeInfo) external payable;

  function resolveDispute(bytes32 incentiveId, bytes memory disputeResolutionInfo) external returns (bool isDismissed);

}