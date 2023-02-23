// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./interfaces/IEscrowedGovIncentive.sol";
import "./interfaces/IVoteVerifier.sol";
import "./lib/ERC20.sol";
import "./lib/SafeTransferLib.sol";

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
