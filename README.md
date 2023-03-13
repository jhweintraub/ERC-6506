# ERC-6506 - The P2P Escrowed Governance-Incentive Standard

Here is the official reference implementation for ERC-6505, the standard for P2P Escrowed Governance-Incentives. This repository contains the most up-to-date version of the EIP, example implementations, and relevant unit tests.

ERC-6506 was designed to be a modular system. Through a series of abstract contracts, your base implementation can pick and choose its functionality. 

Some of the options include
  1. Transparent vs. Private Incentives
  2. On Chain vs. Off Chain Voting
  3. Optional dispute mechanisms for when certain cases can't be resolved independently.
  
 This repo contains four different types of escrowed-incentives and their associated tests, written with Foundry.
  1. Transparent On-Chain
  2. Private On-Chain
  3. Transparent off-Chain
  4. Private off-chain.
  
  A transparent Incentive is one where all the data is committed to on chain, and viewable by everyone. The user provides all the data in the beginning and the hash-committment is calculated and stored on-chain alongside the underlying data. Private incentives are the opposite. When the user creates an incentive, they only provide the committment. The committment does not need to be revealed until either the recipient claims the incentive tokens, or the incentivizer attempts to claw-back their tokens due to non-compliance.
  
  An on-chain incentive is relatively simple. When voting is done entirely on-chain, the system merely checks the voting contract to confirm proof-of-vote. Good examples include Curve governance. Off-chain voting on the other hand refers to voting systems such as Snapshot. On-Chain voting preserves the escrow guarantee, but uses optimistic fraud-proofs and challenge windows to ensure compliance. In order for a user to claim their incentive, the dispute window must have successfully closed without a valid fraud-proof being submitted. Full details on this implementation can be found in the full specification document for EIP-6505. As a PoC, the On-Chain incentive tests were built with the OpenZeppelin GovernorBravo library. Live implementations should be sure to perform integration tests with actually deployed governance systems.
  
This document is meant as a proof-of-concept and should not be used for live-production. 

This repository uses an external library I wrote, [SnapshotSignatureVerifier](https://github.com/jhweintraub/SnapshotSignatureVerifier) for verifying signatures in accordance with EIP-712

## Commit-Reveal Scheme Structure

<img src="https://i.imgur.com/fMC9eBC.png" width="600">


## Reveal Structure

<img src="https://i.imgur.com/d0wEXxv.png" width="600">

## Dispute Mechanism

<img src="https://i.imgur.com/7o90Bl6.png" width="600">
