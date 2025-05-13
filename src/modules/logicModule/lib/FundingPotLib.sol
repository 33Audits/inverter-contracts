// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.23;

import {IERC721} from "@oz/token/ERC721/IERC721.sol";
import {MerkleProof} from "@oz/utils/cryptography/MerkleProof.sol";
import {IERC20PaymentClientBase_v2} from
    "../interfaces/IERC20PaymentClientBase_v2.sol";
import {ILM_PC_FundingPot_v1} from "../interfaces/ILM_PC_FundingPot_v1.sol";

library FundingPotLib {
    /// @notice Verifies NFT ownership for access control.
    /// @dev    Safely checks the NFT balance of a user using a try-catch block.
    /// @param  nft_ Address of the NFT contract.
    /// @param  user_ Address of the user to check for NFT ownership.
    /// @return Boolean indicating whether the user owns an NFT.
    function checkNftOwnership(address nft_, address user_)
        internal
        view
        returns (bool)
    {
        if (nft_ == address(0) || user_ == address(0)) return false;
        try IERC721(nft_).balanceOf(user_) returns (uint b) {
            return b > 0;
        } catch {
            return false;
        }
    }

    /// @notice Verifies a Merkle p roof for access control.
    /// @dev    Validates that the user's address is part of the Merkle tree.
    /// @param  root_ The Merkle root to validate against.
    /// @param  proof_ The Merkle proof to verify.
    /// @param  user_ The address of the user to check.
    /// @param  roundId_ The ID of the round to check.
    /// @return Boolean indicating whether the proof is valid.
    function validateMerkleProof(
        bytes32 root_,
        bytes32[] memory proof_,
        address user_,
        uint32 roundId_
    ) internal pure returns (bool) {
        return MerkleProof.verify(
            proof_, root_, keccak256(abi.encodePacked(user_, roundId_))
        );
    }

    /// @notice Creates time parameter data for a payment order.
    /// @dev    Sets default values for start, cliff, and end if they are zero.
    /// @param  start_ The start time of the payment order.
    /// @param  cliff_ The cliff time of the payment order.
    /// @param  end_ The end time of the payment order.
    /// @return flags The flags for the payment order.
    /// @return data The final data for the payment order.
    function createTimeParameterData(uint start_, uint cliff_, uint end_)
        internal
        view
        returns (bytes32 flags, bytes32[] memory data)
    {
        if (start_ == 0) start_ = block.timestamp;
        if (end_ == 0) end_ = block.timestamp;

        flags = 0;
        bytes32[] memory temp = new bytes32[](3);
        uint8 count = 0;

        if (start_ > 0) {
            flags |= bytes32(uint(1) << 1);
            temp[count++] = bytes32(start_);
        }
        if (cliff_ > 0) {
            flags |= bytes32(uint(1) << 2);
            temp[count++] = bytes32(cliff_);
        }
        if (end_ > 0) {
            flags |= bytes32(uint(1) << 3);
            temp[count++] = bytes32(end_);
        }

        data = new bytes32[](count);
        for (uint8 i = 0; i < count; i++) {
            data[i] = temp[i];
        }
    }

    /// @dev    Validate uint start input.
    /// @param  s_ uint to validate.
    /// @param  c_ uint to validate.
    /// @param  e_ uint to validate.
    /// @return True if uint is valid.
    function validTimes(uint s_, uint c_, uint e_)
        internal
        pure
        returns (bool)
    {
        return s_ + c_ <= e_;
    }

    function checkAccessCriteriaEligibility(
        uint8 type_,
        address nft_,
        bytes32 root_,
        bytes32[] memory proof_,
        mapping(address => bool) storage allowed_,
        address user_,
        uint32 roundId_
    ) internal view returns (bool) {
        if (type_ == 1) return true; // OPEN
        if (type_ == 2) return checkNftOwnership(nft_, user_); // NFT
        if (type_ == 3) {
            return validateMerkleProof(root_, proof_, user_, roundId_);
        } // MERKLE
        if (type_ == 4) return allowed_[user_]; // LIST
        return false;
    }

    function checkRoundClosureConditions(uint end_, uint cap_, uint total_)
        internal
        view
        returns (bool)
    {
        return (cap_ > 0 && total_ == cap_)
            || (end_ > 0 && block.timestamp >= end_);
    }

    /// @notice Validates the round parameters.
    /// @param  round_ The round to validate.
    /// @dev    Reverts if the round parameters are invalid.
    function validateRoundParameters(ILM_PC_FundingPot_v1.Round storage round_)
        internal
        view
    {
        // Validate round start time is in the future
        // @note: The below condition wont allow _roundStart == block.timestamp
        if (round_.roundStart <= block.timestamp) {
            revert
                ILM_PC_FundingPot_v1
                .Module__LM_PC_FundingPot__RoundStartMustBeInFuture();
        }

        // Validate that either end time or cap is set
        if (round_.roundEnd == 0 && round_.roundCap == 0) {
            revert
                ILM_PC_FundingPot_v1
                .Module__LM_PC_FundingPot__RoundMustHaveEndTimeOrCap();
        }

        // If end time is set, validate it's after start time
        if (round_.roundEnd > 0 && round_.roundEnd < round_.roundStart) {
            revert
                ILM_PC_FundingPot_v1
                .Module__LM_PC_FundingPot__RoundEndMustBeAfterStart();
        }

        // Validate hook contract and function consistency
        if (
            round_.hookContract != address(0) && round_.hookFunction.length == 0
        ) {
            revert
                ILM_PC_FundingPot_v1
                .Module__LM_PC_FundingPot__HookFunctionRequiredWithHookContract();
        }

        if (round_.hookContract == address(0) && round_.hookFunction.length > 0)
        {
            revert
                ILM_PC_FundingPot_v1
                .Module__LM_PC_FundingPot__HookContractRequiredWithHookFunction();
        }
    }

    /// @notice Validates the round parameters before editing.
    /// @param  round_ The round to validate.
    /// @dev    Reverts if the round parameters are invalid.
    function validateEditRoundParameters(
        ILM_PC_FundingPot_v1.Round storage round_
    ) internal view {
        if (round_.roundEnd == 0 && round_.roundCap == 0) {
            revert
                ILM_PC_FundingPot_v1
                .Module__LM_PC_FundingPot__RoundNotCreated();
        }

        if (block.timestamp > round_.roundStart) {
            revert
                ILM_PC_FundingPot_v1
                .Module__LM_PC_FundingPot__RoundAlreadyStarted();
        }
    }

    /// @notice Sets or edits an access criteria for a given round.
    /// @param round_ Storage reference to the round being modified.
    /// @param roundIdToNextAccessCriteriaId_ Storage reference to the mapping tracking next AC ID.
    /// @param roundId_ The ID of the round.
    /// @param accessCriteriaType_ The type of access criteria (NFT, MERKLE, etc.).
    /// @param accessCriteriaId_ The ID to edit (0 for new).
    /// @param nftContract_ NFT contract address (if type is NFT).
    /// @param merkleRoot_ Merkle root (if type is MERKLE).
    /// @param allowedAddresses_ List of addresses (if type is LIST).
    /// @return criteriaId The ID of the set/edited criteria.
    /// @return isEdit True if an existing criteria was edited.
    function setAccessCriteria(
        ILM_PC_FundingPot_v1.Round storage round_,
        mapping(uint32 => uint8) storage roundIdToNextAccessCriteriaId_,
        uint32 roundId_,
        uint8 accessCriteriaType_,
        uint8 accessCriteriaId_, // Optional: 0 for new, non-zero for edit
        address nftContract_,
        bytes32 merkleRoot_,
        address[] calldata allowedAddresses_
    ) internal returns (uint8 criteriaId, bool isEdit) {
        if (accessCriteriaType_ > 4) {
            revert
                ILM_PC_FundingPot_v1
                .Module__LM_PC_FundingPot__InvalidAccessCriteriaId();
        }

        // If accessCriteriaId_ is 0, create a new access criteria
        // Otherwise, edit the existing one
        if (accessCriteriaId_ == 0) {
            criteriaId = ++roundIdToNextAccessCriteriaId_[roundId_];
        } else {
            criteriaId = accessCriteriaId_;
            isEdit = true;

            if (
                round_.accessCriterias[criteriaId].accessCriteriaType
                    == ILM_PC_FundingPot_v1.AccessCriteriaType.UNSET
            ) {
                revert
                    ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__InvalidAccessCriteriaId();
            }
        }

        // Validate required data based on access criteria type
        ILM_PC_FundingPot_v1.AccessCriteriaType accessCriteriaType =
            ILM_PC_FundingPot_v1.AccessCriteriaType(accessCriteriaType_);
        if (accessCriteriaType == ILM_PC_FundingPot_v1.AccessCriteriaType.NFT) {
            if (nftContract_ == address(0)) {
                revert
                    ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__MissingRequiredAccessCriteriaData();
            }
        } else if (
            accessCriteriaType == ILM_PC_FundingPot_v1.AccessCriteriaType.MERKLE
        ) {
            if (merkleRoot_ == bytes32(0)) {
                revert
                    ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__MissingRequiredAccessCriteriaData();
            }
        } else if (
            accessCriteriaType == ILM_PC_FundingPot_v1.AccessCriteriaType.LIST
        ) {
            if (allowedAddresses_.length == 0) {
                revert
                    ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__MissingRequiredAccessCriteriaData();
            }
        }

        // Clear all existing data to prevent stale data
        round_.accessCriterias[criteriaId].nftContract = address(0);
        round_.accessCriterias[criteriaId].merkleRoot = bytes32(0);
        // @note: When changing allowlists, call removeAllowlistedAddresses first to clear previous entries

        // Set the access criteria type
        round_.accessCriterias[criteriaId].accessCriteriaType =
            accessCriteriaType;

        // Set only the relevant data based on the access criteria type
        if (accessCriteriaType == ILM_PC_FundingPot_v1.AccessCriteriaType.NFT) {
            round_.accessCriterias[criteriaId].nftContract = nftContract_;
        } else if (
            accessCriteriaType == ILM_PC_FundingPot_v1.AccessCriteriaType.MERKLE
        ) {
            round_.accessCriterias[criteriaId].merkleRoot = merkleRoot_;
        } else if (
            accessCriteriaType == ILM_PC_FundingPot_v1.AccessCriteriaType.LIST
        ) {
            // For LIST type, update the allowed addresses
            for (uint i = 0; i < allowedAddresses_.length; i++) {
                round_.accessCriterias[criteriaId].allowedAddresses[allowedAddresses_[i]]
                = true;
            }
        }
    }

    /// @notice Removes addresses from an allowlist access criteria.
    /// @param round_ Storage reference to the round being modified.
    /// @param accessCriteriaId_ The ID of the access criteria.
    /// @param addressesToRemove_ The list of addresses to remove.
    function removeAllowlistedAddresses(
        ILM_PC_FundingPot_v1.Round storage round_,
        uint8 accessCriteriaId_,
        address[] calldata addressesToRemove_
    ) internal {
        // Verify the access criteria exists and is of type LIST
        if (
            round_.accessCriterias[accessCriteriaId_].accessCriteriaType
                != ILM_PC_FundingPot_v1.AccessCriteriaType.LIST
        ) {
            // If it's UNSET or not LIST, it's an invalid operation for allowlist removal.
            // Reverting with InvalidAccessCriteriaId is appropriate as the criteria is not suitable.
            revert
                ILM_PC_FundingPot_v1
                .Module__LM_PC_FundingPot__InvalidAccessCriteriaId();
        }

        for (uint i = 0; i < addressesToRemove_.length; i++) {
            round_.accessCriterias[accessCriteriaId_].allowedAddresses[addressesToRemove_[i]]
            = false;
        }
    }

    /// @notice Sets the privileges for a specific access criteria.
    /// @param privileges_ Storage reference to the privileges struct.
    /// @param personalCap_ The personal contribution cap.
    /// @param overrideContributionSpan_ Whether contribution span can be overridden.
    /// @param start_ Custom start time.
    /// @param cliff_ Custom cliff time.
    /// @param end_ Custom end time.
    function setAccessCriteriaPrivileges(
        ILM_PC_FundingPot_v1.AccessCriteriaPrivileges storage privileges_,
        uint personalCap_,
        bool overrideContributionSpan_,
        uint start_,
        uint cliff_,
        uint end_
    ) internal {
        if (!validTimes(start_, cliff_, end_)) {
            revert ILM_PC_FundingPot_v1.Module__LM_PC_FundingPot__InvalidTimes();
        }

        privileges_.personalCap = personalCap_;
        privileges_.overrideContributionSpan = overrideContributionSpan_;
        privileges_.start = start_;
        privileges_.cliff = cliff_;
        privileges_.end = end_;
    }
}
