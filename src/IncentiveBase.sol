// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./interfaces/IEscrowedGovIncentive.sol";
import "./interfaces/IVoteVerifier.sol";
import "./lib/ERC20.sol";
import "./lib/SafeTransferLib.sol";

import "openzeppelin/contracts/security/ReentrancyGuard.sol";
import "openzeppelin/contracts/access/Ownable.sol";
import "openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "forge-std/console.sol";

abstract contract IncentiveBase is IEscrowedGovIncentive, Ownable {
    using SafeTransferLib for ERC20;

    address public immutable feeRecipient;
    address public verifier;
    address public bondToken;

    uint public feeBP;
    uint public bondAmount;
    uint public constant BASIS_POINTS = 1e18; //to be used for fee calculations

    mapping(address => mapping(address => bool)) public allowedClaimers;
    mapping(bytes32 => Incentive) internal incentives;
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
        bondToken = _bondToken;
    }

    /*///////////////////////////////////////////////////////////////
                            Dispute Helpers
    //////////////////////////////////////////////////////////////*/


    //Dispute Mechanism
    //KEY POINT: Even if it's a private incentive it doesn't get revealed until the callback
    function beginPublicDispute(bytes32 incentiveId) internal {
        Incentive memory incentive = incentives[incentiveId];

        require(!disputes[incentiveId], "a dispute has already been initiated");
        require(incentive.deadline <= block.timestamp, "not enough time has passed yet to file a dispute");

        //Necesarry to prevent spam dispute filings
        console.log("msg sender: ", msg.sender);
        console.log("incentivizer: ", incentive.incentivizer);
        require(msg.sender == incentive.incentivizer, "only the incentivizer can file a dispute over the incentive");
       

        //Transfer Bond to this
        console.log("bond token: ", bondToken);
        console.log("bondAmount: ", bondAmount);
        ERC20(bondToken).safeTransferFrom(msg.sender, address(this), bondAmount);

        disputes[incentiveId] = true;
        
        emit disputeInitiated(incentiveId, msg.sender, incentive.recipient);
    }

    //Resolving off chain dispute = check against merkle tree
    function resolveOffChainDispute(bytes32 incentiveId, bytes memory disputeResolutionInfo) internal returns (bool isDismissed) {
        Incentive storage incentive = incentives[incentiveId];
        uint callbackTime = disputeCallbackTimes[incentiveId];

        require(!incentive.claimed, "incentive has already been claimed");
        require(callbackTime != 0, "callback has not yet occured");
        require(disputes[incentiveId], "no dispute was filed for you to resolve");

        if (msg.sender == incentive.incentivizer) {
            //check that the window for the recipient has closed
            require(block.timestamp >= (callbackTime + 3 days), "window has not yet closed");
            //You don't need to check the status since the incentive.claimed value will handle it

            incentive.claimed = true;

            //Give them the bond
            ERC20(bondToken).safeTransfer(incentive.incentivizer, bondAmount);
            ERC20(incentive.incentiveToken).safeTransfer(incentive.incentivizer, incentive.amount);

            emit disputeResolved(incentiveId, msg.sender, incentive.recipient, true);
            isDismissed = true;
        }

        //If it's the recipient
        else if (msg.sender == incentive.recipient || allowedClaimers[incentive.recipient][msg.sender]) {
            //check that the window has not yet closed to show proof
            require(block.timestamp <= (callbackTime + 3 days), "your window has closed");
            (bytes32[] memory merkleProof) = abi.decode(disputeResolutionInfo, (bytes32[]));

            //Verify that they are in the merkle tree of voters
            require(MerkleProof.verify(merkleProof, disputeMerklesRoots[incentiveId], keccak256(abi.encode(incentive.recipient))));
        
            incentive.claimed = true;
            //Send them the tokens
            ERC20(bondToken).safeTransfer(feeRecipient, bondAmount);
            ERC20(incentive.incentiveToken).safeTransfer(incentive.recipient, incentive.amount);

            emit disputeResolved(incentiveId, incentive.incentivizer, incentive.recipient, false);
            isDismissed = false;
        }

        else {
            revert("Cannot claim incentive you are not involved in");
        }

        //Tokens should already be retrieved by this point so it's ok to make the calls
        //It's certainly not the most secure to get the tokens before verifying but it's the only way this system works
        //nonReentrant should be fine. Maybe return later and try and fix
    }

    function resolveOnChainDispute(bytes32 incentiveId, bytes memory disputeResolutionInfo) internal virtual returns (bool isDismissed) {
        require(arbiters[msg.sender], "not allowed to resolve a dispute");
        require(disputes[incentiveId], "cannot resolve a dispute that has not been filed");

        Incentive storage incentive = incentives[incentiveId];

        (address winner) = abi.decode(disputeResolutionInfo, (address));
        require(winner == incentive.incentivizer || winner == incentive.recipient, "cannot resolve a dispute for a non-involved party");
        isDismissed = !(winner == incentive.incentivizer);//it's dismissed if the winner is NOT the incentivizer

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

    function setMerkleRoot(bytes32 incentiveId, bytes32 root) external {
        require(arbiters[msg.sender]);
        disputeMerklesRoots[incentiveId] = root;
        disputeCallbackTimes[incentiveId] = uint64(block.timestamp);
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
        _;

        Incentive memory incentive = incentives[incentiveId];

        if (msg.sender != incentive.recipient) {
            require(allowedClaimers[incentive.recipient][msg.sender], "Not allowed to claim on behalf of recipient");
        }  
    }

    /*///////////////////////////////////////////////////////////////
                            Helper View functions
    //////////////////////////////////////////////////////////////*/

    function getIncentive(bytes32 incentiveId) external view returns (Incentive memory) {
        return incentives[incentiveId];
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

    function addArbiter(address _arbiter) external onlyOwner {
        arbiters[_arbiter] = true;
    }
}
