// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./interfaces/IEscrowedGovIncentive.sol";
import "./interfaces/IVoteVerifier.sol";
import "./lib/ERC20.sol";
import "./lib/SafeTransferLib.sol";

import "openzeppelin/contracts/security/ReentrancyGuard.sol";
import "openzeppelin/contracts/access/Ownable.sol";

abstract contract IncentiveBase is IEscrowedGovIncentive, Ownable {
    using SafeTransferLib for ERC20;

    address public immutable feeRecipient;
    address public verifier;
    address public bondToken;

    uint public feeBP;
    uint public bondAmount;
    uint public constant BASIS_POINTS = 1e18; //to be used for fee calculations

    mapping(address => mapping(address => bool)) public allowedClaimers;
    mapping(bytes32 => Incentive) public incentives;
    mapping(address => bool) public arbiters;

    mapping(bytes32 => bool) public disputes;
     mapping(bytes32 => bytes32) public disputeMerklesRoots;
    mapping(bytes32 => uint64) public disputeCallbackTimes;

    constructor(address _feeRecipient, address _verifier, uint _feeBP, uint _bondAmount, address _bondToken) {
        require(_feeRecipient != address(0), "Address cannot be zero");
        require(_verifier != address(0), "Address cannot be zero");
        require(_bondToken != address(0), "Address cannot be zero");

        require(_bondAmount != 0, "Bond Amount cannot be zero");

        feeRecipient = _feeRecipient;
        feeBP = _feeBP;
        verifier = _verifier;
        bondAmount = _bondAmount;
    }

    /*///////////////////////////////////////////////////////////////
                            Dispute Helpers
    //////////////////////////////////////////////////////////////*/
    function verifyVote(bytes32 incentive, bytes calldata voteInfo) public view returns (bool isVerifiable, bytes memory proofData) {
        IEscrowedGovIncentive.Incentive memory incentive = incentives[incentive];


        //TODO - Include more info into voteInfo that is necesarry like ABI-encoding the contract or the DAO
        (isVerifiable, proofData) = IVoteVerifier(verifier).verifyVote(incentive, voteInfo);
    }

    //Dispute Mechanism
    //KEY POINT: Even if it's a private incentive it doesn't get revealed until the callback
    function beginPublicDispute(bytes32 incentiveId) external virtual payable {
        Incentive memory incentive = incentives[incentiveId];

        require(!disputes[incentiveId], "a dispute has already been initiated");
        require(incentive.deadline <= block.timestamp, "not enough time has passed yet to file a dispute");

        //Necesarry to prevent spam dispute filings
        require(msg.sender == incentive.incentivizer, "only the incentivizer can file a dispute over the incentive");

        //Transfer Bond to this
        ERC20(bondToken).safeTransferFrom(msg.sender, address(this), bondAmount);
        
        emit disputeInitiated(incentiveId, msg.sender, incentive.recipient);
    }

    //Resolving off chain dispute = check against merkle tree
    function resolveOffChainDispute(bytes32 incentiveId, bytes calldata disputeResolutionInfo) internal returns (bool isDismissed) {
        Incentive memory incentive = incentives[incentiveId];
        uint callbackTime = disputeCallbackTimes[incentiveId];

        if (msg.sender == incentive.incentivizer) {
            require(callbackTime != 0 && callbackTime <= (block.timestamp + 3 days), "window has not yet closed");


            //retrieve the tokens
        }

        // (bytes[] calldata proof) = abi.decode(disputeResolutionInfo, (bytes32[]));
        
    }

    function resolveOnChainDispute(bytes32 incentiveId, bytes calldata disputeResolutionInfo) internal virtual returns (bool isDismissed) {
        require(arbiters[msg.sender], "not allowed to resolve a dispute");
        require(disputes[incentiveId], "cannot resolve a dispute that has not been filed");

        Incentive storage incentive = incentives[incentiveId];

        (address winner) = abi.decode(disputeResolutionInfo, (address));
        require(winner == incentive.incentivizer || winner == incentive.recipient, "cannot resolve a dispute for a non-involved party");
        bool isDismissed = (winner == incentive.incentivizer);

        //Mark as claimed to prevent re-entry
        incentive.claimed = true;

        //If the 
        if (isDismissed) {
            //Bond is kept by protocol and tokens given to the recipient
            ERC20(bondToken).safeTransfer(feeRecipient, bondAmount);
            ERC20(incentive.incentiveToken).safeTransfer(incentive.recipient, incentive.amount);
        } 
        else {
            //Return the bond and the tokens to the incentivizer
            ERC20(bondToken).safeTransfer(incentive.incentivizer, bondAmount);
            ERC20(incentive.incentiveToken).safeTransfer(incentive.incentivizer, incentive.amount);
        }

        emit disputeResolved(incentiveId, incentive.incentivizer, incentive.recipient, isDismissed);
    }

    //I Think this is dead code
    modifier noActiveDispute(bytes32 incentiveId) {
        require(!disputes[incentiveId], "Cannot proceed while dispute is being processed");
        _;
    }

    /*///////////////////////////////////////////////////////////////
                            Claimer functions
    //////////////////////////////////////////////////////////////*/
    function modifyClaimer(address claimer, bool designation) external returns (bool) {
        if (designation) {
            allowedClaimers[msg.sender][claimer] = true;
        }
        else {
            allowedClaimers[msg.sender][claimer] = false;
        }
    }

    modifier isAllowedClaimer(bytes32 incentiveId) {
        Incentive memory incentive = incentives[incentiveId];

        if (msg.sender != incentive.recipient) {
            require(allowedClaimers[incentive.recipient][msg.sender], "Not allowed to claim on behalf of recipient");
        }  
        _;
    }
    /*///////////////////////////////////////////////////////////////
                            Admin functions
    //////////////////////////////////////////////////////////////*/

    function changeVerifier(address _newVerifier) external onlyOwner {
        require(_newVerifier != address(0));
        verifier = _newVerifier;
    }

    function changeFeeBP(uint _newFeeBP) external onlyOwner {
        feeBP = _newFeeBP;
    }

    function changeBondAmount(uint _newBondAmount) external onlyOwner {
        bondAmount = _newBondAmount;
    }

    function changeBondToken(address _newBondToken) external onlyOwner {
        bondToken = _newBondToken;
    }
}
