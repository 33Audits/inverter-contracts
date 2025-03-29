// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.23;

// Internal
import {
    ModuleTest,
    IModule_v1,
    IOrchestrator_v1
} from "test/modules/ModuleTest.sol";
import {OZErrors} from "test/utils/errors/OZErrors.sol";

// External
import {Clones} from "@oz/proxy/Clones.sol";

// Mocks
import {
    IERC20PaymentClientBase_v2,
    ERC20PaymentClientBaseV2Mock,
    ERC20Mock
} from "test/utils/mocks/modules/paymentClient/ERC20PaymentClientBaseV2Mock.sol";
import {ERC721Mock} from
    "test/utils/mocks/modules/logicModules/LM_PC_FundingPot_v2NFTMock.sol";

// System under Test (SuT)
import {LM_PC_FundingPot_v1_Exposed} from
    "test/modules/logicModule/LM_PC_FundingPot_v1_Exposed.sol";
import {ILM_PC_FundingPot_v1} from
    "src/modules/logicModule/interfaces/ILM_PC_FundingPot_v1.sol";

import {console2} from "forge-std/console2.sol";
/**
 * @title   Inverter Funding Pot Logic Module Tests
 *
 * @notice  Tests for the funding pot logic module
 *
 * @dev     This test contract follows the standard testing pattern showing:
 *          - Initialization tests
 *          - External function tests
 *          - Internal function tests through exposed functions
 *          - Use of Gherkin for test documentation
 *
 * @author  Inverter Network
 */

contract LM_PC_FundingPot_v1_Test is ModuleTest {
    // -------------------------------------------------------------------------
    // Constants

    bytes32 internal constant FUNDING_POT_ADMIN_ROLE = "FUNDING_POT_ADMIN";
    address contributor_;

    bytes32 PROOF_ONE =
        0x0fd7c981d39bece61f7499702bf59b3114a90e66b51ba2c53abdf7b62986c00a;
    bytes32 PROOF_TWO =
        0xe5ebd1e1b5a5478a944ecab36a9a954ac3b6b8216875f6524caa7a1d87096576;
    bytes32[] PROOF = [PROOF_ONE, PROOF_TWO];
    bytes32 ROOT =
        0xaa5d581231e596618465a56aa0f5870ba6e20785fe436d5bfb82b08662ccc7c4;

    // -------------------------------------------------------------------------
    // State
    struct RoundParameters {
        uint roundStart;
        uint roundEnd;
        uint roundCap;
        address hookContract;
        bytes hookFunction;
        bool closureMechanism;
        bool globalAccumulativeCaps;
    }
    // SuT

    LM_PC_FundingPot_v1_Exposed fundingPot;

    // Mocks
    ERC20Mock fundingPotToken =
        new ERC20Mock("FundingPot Mock Token", "FUNDINGPOT MOCK");

    ERC721Mock mockNFTContract = new ERC721Mock("NFT Mock", "NFT");

    // -------------------------------------------------------------------------
    // Setup
    function setUp() public {
        // Deploy the SuT
        address impl = address(new LM_PC_FundingPot_v1_Exposed());
        fundingPot = LM_PC_FundingPot_v1_Exposed(Clones.clone(impl));

        // Mint tokens to the contributor
        contributor_ = address(0xBeef);
        fundingPotToken.mint(contributor_, 10_000);

        // Setup the module to test
        _setUpOrchestrator(fundingPot);

        // Initiate the Logic Module with the metadata and config data
        fundingPot.init(_orchestrator, _METADATA, abi.encode(""));

        _authorizer.setIsAuthorized(address(this), true);

        // Set the block timestamp
        vm.warp(block.timestamp + _orchestrator.MODULE_UPDATE_TIMELOCK());
    }

    // -------------------------------------------------------------------------
    // Test: Initialization

    function testInit() public override(ModuleTest) {
        assertEq(address(fundingPot.orchestrator()), address(_orchestrator));
    }

    function testSupportsInterface() public {
        assertTrue(
            fundingPot.supportsInterface(type(ILM_PC_FundingPot_v1).interfaceId)
        );
        assertTrue(
            fundingPot.supportsInterface(type(ILM_PC_FundingPot_v1).interfaceId)
        );
    }

    function testReinitFails() public override(ModuleTest) {
        vm.expectRevert(OZErrors.Initializable__InvalidInitialization);
        fundingPot.init(_orchestrator, _METADATA, abi.encode(""));
    }

    // -------------------------------------------------------------------------
    // Test External (public + external)

    /* Test createRound()
    ├── Given user does not have FUNDING_POT_ADMIN_ROLE
    │   └── When user attempts to create a round
    │       └── Then it should revert
    └── Given user has FUNDING_POT_ADMIN_ROLE
    ├── And round start < block.timestamp
    │   └── When user attempts to create a round
    │       └── Then it should revert
    ├── And round end time == 0 
    │   ├── And round cap == 0
    │   │   └── When user attempts to create a round
    │   │       └── Then it should revert
    ├── And round end time is set 
    │   ├── And round end != 0
    │   ├── And round end < round start
    │   │   └── When user attempts to create a round
    │   │       └── Then it should revert
    ├── And hook contract is set but hook function is not set
    │   └── When user attempts to create a round
    │       └── Then it should revert
    ├── And hook function is set but hook contract is not set
    │   └── When user attempts to create a round
    │       └── Then it should revert
    └── Given all the valid parameters are provided
        └── When user attempts to create a round
            └── Then it should not be active and should return the round id
    */

    function testCreateRound_revertsGivenUserIsNotFundingPotAdmin(address user_)
        public
    {
        vm.assume(user_ != address(0) && user_ != address(this));
        vm.startPrank(user_);
        bytes32 roleId = _authorizer.generateRoleId(
            address(fundingPot), fundingPot.FUNDING_POT_ADMIN_ROLE()
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector, roleId, user_
            )
        );
        (
            uint roundStart,
            uint roundEnd,
            uint roundCap,
            address hookContract,
            bytes memory hookFunction,
            bool closureMechanism,
            bool globalAccumulativeCaps
        ) = _helper_createDefaultFundingRound(1000);
        _helper_callCreateRound(
            roundStart,
            roundEnd,
            roundCap,
            hookContract,
            hookFunction,
            closureMechanism,
            globalAccumulativeCaps
        );
        vm.stopPrank();
    }

    function testCreateRound_revertsGivenRoundStartIsInThePast(uint roundStart_)
        public
    {
        vm.assume(roundStart_ < block.timestamp);
        (
            uint roundStart,
            uint roundEnd,
            uint roundCap,
            address hookContract,
            bytes memory hookFunction,
            bool closureMechanism,
            bool globalAccumulativeCaps
        ) = _helper_createDefaultFundingRound(1000);
        roundStart = roundStart_;
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundStartMustBeInFuture
                    .selector
            )
        );
        _helper_callCreateRound(
            roundStart,
            roundEnd,
            roundCap,
            hookContract,
            hookFunction,
            closureMechanism,
            globalAccumulativeCaps
        );
    }

    function testCreateRound_revertsGivenRoundEndTimeAndCapAreBothZero()
        public
    {
        (
            uint roundStart,
            uint roundEnd,
            uint roundCap,
            address hookContract,
            bytes memory hookFunction,
            bool closureMechanism,
            bool globalAccumulativeCaps
        ) = _helper_createDefaultFundingRound(1000);
        roundEnd = 0;
        roundCap = 0;
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundMustHaveEndTimeOrCap
                    .selector
            )
        );
        _helper_callCreateRound(
            roundStart,
            roundEnd,
            roundCap,
            hookContract,
            hookFunction,
            closureMechanism,
            globalAccumulativeCaps
        );
    }

    function testCreateRound_revertsGivenRoundEndTimeIsBeforeRoundStart(
        uint roundEnd_
    ) public {
        (
            uint roundStart,
            uint roundEnd,
            uint roundCap,
            address hookContract,
            bytes memory hookFunction,
            bool closureMechanism,
            bool globalAccumulativeCaps
        ) = _helper_createDefaultFundingRound(1000);
        vm.assume(roundEnd_ != 0 && roundEnd_ < roundStart);
        roundEnd = roundEnd_;
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundEndMustBeAfterStart
                    .selector
            )
        );
        _helper_callCreateRound(
            roundStart,
            roundEnd,
            roundCap,
            hookContract,
            hookFunction,
            closureMechanism,
            globalAccumulativeCaps
        );
    }

    function testCreateRound_revertsGivenHookContractIsSetButHookFunctionIsEmpty(
    ) public {
        (
            uint roundStart,
            uint roundEnd,
            uint roundCap,
            address hookContract,
            bytes memory hookFunction,
            bool closureMechanism,
            bool globalAccumulativeCaps
        ) = _helper_createDefaultFundingRound(1000);
        hookContract = address(1);
        hookFunction = bytes("");
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__HookFunctionRequiredWithHookContract
                    .selector
            )
        );
        _helper_callCreateRound(
            roundStart,
            roundEnd,
            roundCap,
            hookContract,
            hookFunction,
            closureMechanism,
            globalAccumulativeCaps
        );
    }

    function testCreateRound_revertsGivenHookFunctionIsSetButHookContractIsEmpty(
    ) public {
        (
            uint roundStart,
            uint roundEnd,
            uint roundCap,
            address hookContract,
            bytes memory hookFunction,
            bool closureMechanism,
            bool globalAccumulativeCaps
        ) = _helper_createDefaultFundingRound(1000);
        hookContract = address(0);
        hookFunction = bytes("test");
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__HookContractRequiredWithHookFunction
                    .selector
            )
        );
        _helper_callCreateRound(
            roundStart,
            roundEnd,
            roundCap,
            hookContract,
            hookFunction,
            closureMechanism,
            globalAccumulativeCaps
        );
    }

    /* Test Fuzz createRound()
        ├── Given all the valid parameters are provided
        │   └── When user attempts to create a round
        │       └── Then it should not be active and should return the round id
        */
    // TODO: Should rename to testFuzzCreateRound
    function testCreateRound(uint roundCap_) public {
        vm.assume(roundCap_ > 0);
        (
            uint roundStart,
            uint roundEnd,
            uint roundCap,
            address hookContract,
            bytes memory hookFunction,
            bool closureMechanism,
            bool globalAccumulativeCaps
        ) = _helper_createDefaultFundingRound(roundCap_);
        _helper_callCreateRound(
            roundStart,
            roundEnd,
            roundCap,
            hookContract,
            hookFunction,
            closureMechanism,
            globalAccumulativeCaps
        );

        uint64 lastRoundId = fundingPot.getRoundCount();
        (
            uint roundStart_,
            uint roundEnd_,
            uint roundCap_,
            address hookContract_,
            bytes memory hookFunction_,
            bool closureMechanism_,
            bool globalAccumulativeCaps_
        ) = fundingPot.getRoundGenericParameters(lastRoundId);

        assertEq(roundStart, roundStart_);
        assertEq(roundEnd, roundEnd_);
        assertEq(roundCap, roundCap_);
        assertEq(hookContract, hookContract_);
        assertEq(hookFunction, hookFunction_);
        assertEq(closureMechanism, closureMechanism_);
        assertEq(globalAccumulativeCaps, globalAccumulativeCaps_);
    }

    /* Test editRound()
    ├── Given user does not have FUNDING_POT_ADMIN_ROLE
    │   └── When user attempts to edit a round
    │       └── Then it should revert
    ├── Given round does not exist
    │   └── When user attempts to edit the round
    │       └── Then it should revert
    ├── Given round is active
    │   └── When user attempts to edit the round
    │       └── Then it should revert
    ├── Given round start time is in the past
    │   └── When user attempts to edit a round with the above parameter
    │       └── Then it should revert
    ├── Given round end time == 0
    │   ├── And round cap == 0
    │   └── When user attempts to edit a round with the above parameters
    │       └── Then it should revert
    ├── Given round end time is set
    │   ├── And round end is before round start
    │   └── When user attempts to edit the round
    │       └── Then it should revert
    ├── Given hook contract is set
    │   ├── And hook function is empty
    │   └── When user attempts to edit the round
    │       └── Then it should revert
    └── Given hook function is set
        ├── And hook contract is empty
            └── When user attempts to edit the round
                └── Then it should revert  
    */

    function testEditRound_revertsGivenUserIsNotFundingPotAdmin(address user_)
        public
    {
        testCreateRound(1000);
        uint64 roundId = fundingPot.getRoundCount();

        RoundParameters memory editedParams = _helper_createEditedRoundParams();

        vm.startPrank(user_);
        bytes32 roleId = _authorizer.generateRoleId(
            address(fundingPot), fundingPot.FUNDING_POT_ADMIN_ROLE()
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector, roleId, user_
            )
        );
        _helper_callEditRound(roundId, editedParams);
        vm.stopPrank();
    }

    function testEditRound_revertsGivenRoundIsNotCreated() public {
        testCreateRound(1000);
        uint64 roundId = fundingPot.getRoundCount() + 1;

        RoundParameters memory editedParams = _helper_createEditedRoundParams();

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundNotCreated
                    .selector
            )
        );
        _helper_callEditRound(roundId, editedParams);
    }

    function testEditRound_revertsGivenRoundIsActive() public {
        testCreateRound(1000);
        uint64 roundId = fundingPot.getRoundCount();

        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        RoundParameters memory editedParams = _helper_createEditedRoundParams();

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundAlreadyStarted
                    .selector
            )
        );
        _helper_callEditRound(roundId, editedParams);
    }

    function testEditRound_revertsGivenRoundStartIsInThePast(uint roundStartP_)
        public
    {
        testCreateRound(1000);
        uint64 roundId = fundingPot.getRoundCount();

        RoundParameters memory editedParams = _helper_createEditedRoundParams();
        vm.assume(roundStartP_ < block.timestamp);
        editedParams.roundStart = roundStartP_;

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundStartMustBeInFuture
                    .selector
            )
        );
        _helper_callEditRound(roundId, editedParams);
    }

    function testEditRound_revertsGivenRoundEndTimeAndCapAreBothZero() public {
        testCreateRound(1000);
        uint64 roundId = fundingPot.getRoundCount();

        RoundParameters memory editedParams = _helper_createEditedRoundParams();
        editedParams.roundEnd = 0;
        editedParams.roundCap = 0;

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundMustHaveEndTimeOrCap
                    .selector
            )
        );
        _helper_callEditRound(roundId, editedParams);
    }

    function testEditRound_revertsGivenRoundEndTimeIsBeforeRoundStart(
        uint roundEnd_,
        uint roundStart_
    ) public {
        vm.assume(
            roundEnd_ != 0 && roundStart_ > block.timestamp
                && roundEnd_ < roundStart_
        );
        testCreateRound(1000);
        uint64 roundId = fundingPot.getRoundCount();

        RoundParameters memory editedParams = _helper_createEditedRoundParams();
        editedParams.roundStart = roundStart_;
        roundEnd_ = bound(roundEnd_, 0, roundStart_ - 1);
        editedParams.roundEnd = roundEnd_;

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundEndMustBeAfterStart
                    .selector
            )
        );
        _helper_callEditRound(roundId, editedParams);
    }

    function testEditRound_revertsGivenHookContractIsSetButHookFunctionIsEmpty()
        public
    {
        testCreateRound(1000);
        uint64 roundId = fundingPot.getRoundCount();

        RoundParameters memory editedParams = _helper_createEditedRoundParams();
        editedParams.hookContract = address(1);
        editedParams.hookFunction = bytes("");

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__HookFunctionRequiredWithHookContract
                    .selector
            )
        );
        _helper_callEditRound(roundId, editedParams);
    }

    function testEditRound_revertsGivenHookFunctionIsSetButHookContractIsEmpty()
        public
    {
        testCreateRound(1000);
        uint64 roundId = fundingPot.getRoundCount();

        RoundParameters memory editedParams = _helper_createEditedRoundParams();
        editedParams.hookContract = address(0);
        editedParams.hookFunction = bytes("test");

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__HookContractRequiredWithHookFunction
                    .selector
            )
        );
        _helper_callEditRound(roundId, editedParams);
    }

    /* Test editRound()
    └── Given a round has been created
    ├── And the round is not active
    └── When an admin provides valid parameters to edit the round
        └── Then all the round details should be successfully updated
            ├── roundStart should be updated to the new value
            ├── roundEnd should be updated to the new value
            ├── roundCap should be updated to the new value
            ├── hookContract should be updated to the new value
            ├── hookFunction should be updated to the new value
            ├── closureMechanism should be updated to the new value
            └── globalAccumulativeCaps should be updated to the new value
    */

    function testEditRound() public {
        testCreateRound(1000);
        uint64 lastRoundId = fundingPot.getRoundCount();

        RoundParameters memory editedParams = _helper_createEditedRoundParams();

        _helper_callEditRound(lastRoundId, editedParams);

        (
            uint roundStart,
            uint roundEnd,
            uint roundCap,
            address hookContract,
            bytes memory hookFunction,
            bool closureMechanism,
            bool globalAccumulativeCaps
        ) = fundingPot.getRoundGenericParameters(lastRoundId);

        assertEq(roundStart, editedParams.roundStart);
        assertEq(roundEnd, editedParams.roundEnd);
        assertEq(roundCap, editedParams.roundCap);
        assertEq(hookContract, editedParams.hookContract);
        assertEq(hookFunction, editedParams.hookFunction);
        assertEq(closureMechanism, editedParams.closureMechanism);
        assertEq(globalAccumulativeCaps, editedParams.globalAccumulativeCaps);
    }

    /* Test setAccessCriteria()
    ├── Given user does not have FUNDING_POT_ADMIN_ROLE
    │   └── When user attempts to set access criteria
    │       └── Then it should revert
    ├── Given round does not exist
    │   └── When user attempts to set access criteria
    │       └── Then it should revert
    ├── Given round is active
    │   └── When user attempts to set access criteria
    │       └── Then it should revert
    ├── Given AccessCriteriaId is NFT and nftContract is 0x0
    │   └── When user attempts to set access criteria
    │       └── Then it should revert
    ├── Given AccessCriteriaId is MERKLE and merkleRoot is 0x0
    │   └── When user attempts to set access criteria
    │       └── Then it should revert
    ├── Given AccessCriteriaId is LIST and allowedAddresses is empty
    │   └── When user attempts to set access criteria
    │       └── Then it should revert
    └── Given all the valid parameters are provided
        └── When user attempts to set access criteria
            └── Then it should not revert
    */

    function testFuzzSetAccessCriteria_revertsGivenUserDoesNotHaveFundingPotAdminRole(
        uint8 accessCriteriaEnum_,
        address user_
    ) public {
        vm.assume(accessCriteriaEnum_ >= 0 && accessCriteriaEnum_ <= 3);
        vm.assume(user_ != address(0) && user_ != address(this));

        testCreateRound(1000);
        uint64 roundId = fundingPot.getRoundCount();
        uint8 accessId = 1;

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(accessCriteriaEnum_);

        vm.startPrank(user_);
        bytes32 roleId = _authorizer.generateRoleId(
            address(fundingPot), fundingPot.FUNDING_POT_ADMIN_ROLE()
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IModule_v1.Module__CallerNotAuthorized.selector, roleId, user_
            )
        );
        fundingPot.setAccessCriteriaForRound(roundId, accessId, accessCriteria);
    }

    function testFuzzSetAccessCriteria_revertsGivenRoundDoesNotExist(
        uint8 accessCriteriaEnum
    ) public {
        vm.assume(accessCriteriaEnum >= 0 && accessCriteriaEnum <= 3);

        uint64 roundId = fundingPot.getRoundCount();
        uint8 accessId = 1;

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(accessCriteriaEnum);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundNotCreated
                    .selector
            )
        );
        fundingPot.setAccessCriteriaForRound(roundId, accessId, accessCriteria);
    }

    function testFuzzSetAccessCriteria_revertsGivenRoundIsActive(
        uint8 accessCriteriaEnum
    ) public {
        vm.assume(accessCriteriaEnum >= 0 && accessCriteriaEnum <= 3);
        testCreateRound(1000);
        uint64 roundId = fundingPot.getRoundCount();
        uint8 accessId = 1;

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(accessCriteriaEnum);

        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundAlreadyStarted
                    .selector
            )
        );
        fundingPot.setAccessCriteriaForRound(roundId, accessId, accessCriteria);
    }

    function testSetAccessCriteria_revertsGivenAccessCriteriaIdIsNFTAndNftContractIsZero(
    ) public {
        uint8 accessCriteriaEnum =
            uint8(ILM_PC_FundingPot_v1.AccessCriteriaId.NFT);
        testCreateRound(1000);
        uint64 roundId = fundingPot.getRoundCount();
        uint8 accessId = 1;

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(accessCriteriaEnum);
        accessCriteria.nftContract = address(0);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__MissingRequiredAccessCriteriaData
                    .selector
            )
        );
        fundingPot.setAccessCriteriaForRound(roundId, accessId, accessCriteria);
    }

    function testSetAccessCriteria_revertsGivenAccessCriteriaIdIsMerkleAndMerkleRootIsZero(
    ) public {
        uint8 accessCriteriaEnum =
            uint8(ILM_PC_FundingPot_v1.AccessCriteriaId.MERKLE);
        testCreateRound(1000);
        uint64 roundId = fundingPot.getRoundCount();
        uint8 accessId = 1;

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(accessCriteriaEnum);
        accessCriteria.merkleRoot = bytes32(uint(0x0));

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__MissingRequiredAccessCriteriaData
                    .selector
            )
        );
        fundingPot.setAccessCriteriaForRound(roundId, accessId, accessCriteria);
    }

    function testSetAccessCriteria_revertsGivenAccessCriteriaIdIsListAndAllowedAddressesIsEmpty(
    ) public {
        uint8 accessCriteriaEnum =
            uint8(ILM_PC_FundingPot_v1.AccessCriteriaId.LIST);
        testCreateRound(1000);
        uint64 roundId = fundingPot.getRoundCount();
        uint8 accessId = 1;

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(accessCriteriaEnum);
        accessCriteria.allowedAddresses = new address[](0);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__MissingRequiredAccessCriteriaData
                    .selector
            )
        );
        fundingPot.setAccessCriteriaForRound(roundId, accessId, accessCriteria);
    }

    function testFuzzSetAccessCriteria(uint8 accessCriteriaEnum) public {
        vm.assume(accessCriteriaEnum >= 0 && accessCriteriaEnum <= 3);
        testCreateRound(1000);
        uint64 roundId = fundingPot.getRoundCount();
        uint8 accessId = 1;

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(accessCriteriaEnum);

        fundingPot.setAccessCriteriaForRound(roundId, accessId, accessCriteria);

        (
            bool isOpen,
            address nftContract,
            bytes32 merkleRoot,
            address[] memory allowedAddresses
        ) = fundingPot.getRoundAccessCriteria(roundId, accessId);

        assertEq(isOpen, accessCriteriaEnum == 0);
        assertEq(nftContract, accessCriteria.nftContract);
        assertEq(merkleRoot, accessCriteria.merkleRoot);
        assertEq(allowedAddresses, accessCriteria.allowedAddresses);
    }

    /*

    ├── Given the round contribution cap has been reached
    │   └── When the user contributes to the round
    │       └── Then the transaction should revert
    │
    ├── Given the round has not started yet
    │   └── When the user contributes to the round
    │       └── Then the transaction should revert
    │
    ├── Given the round has ended
    │   └── When the user contributes to the round
    │       └── Then the transaction should revert
    │
    ├── Given a round has been configured with generic round configuration and access criteria
    │   And the round has started
    │   And the round has not ended
    │   And the user has approved their contribution
    │   And the total contribution cap is not yet reached
    │   ├── Given the access criteria is an NFT
    │   │   └── And the user does not fulfill the access criteria
    │   │       └── When the user contributes to the round
    │   │           └── Then the transaction should revert
    │   │
    │   ├── Given the access criteria is a Merkle Root
    │   │   └── And the user does not fulfill the access criteria
    │   │       └── When the user contributes to the round
    │   │           └── Then the transaction should revert
    │   │
    │   ├── Given the access criteria is a List
    │   │   └── And the user does not fulfill the access criteria
    │   │       └── When the user contributes to the round
    │   │           └── Then the transaction should revert
    │   │
    │   └── Given a user has already contributed up to their personal cap
    │       └── When the user attempts to contribute again
    │           └── Then the transaction should revert
    */
    function testFuzzContributeToRound_revertsWhenRoundContributionCapReached(
        uint roundCap_
    ) public {
        testCreateRound(10);

        uint64 roundId = fundingPot.getRoundCount();
        uint8 accessId = 1;
        uint amount = 100;

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(0);

        fundingPot.setAccessCriteriaForRound(roundId, accessId, accessCriteria);

        (uint roundStart,, uint roundCap,,,,) =
            fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Approve
        vm.prank(contributor_);
        fundingPotToken.approve(address(fundingPot), amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundCapReached
                    .selector
            )
        );

        vm.prank(contributor_);
        fundingPot.contributeToRound(
            roundId,
            amount,
            accessId,
            address(fundingPotToken),
            new bytes32[](0)
        );
    }

    function testFuzzContributeToRound_revertsWhenUserContributionExceedsTheRoundCap(
        uint roundCap_
    ) public {
        testCreateRound(200);

        uint64 roundId = fundingPot.getRoundCount();
        uint8 accessId = 1;
        uint amount = 201;

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(0);

        fundingPot.setAccessCriteriaForRound(roundId, accessId, accessCriteria);

        (uint roundStart,, uint roundCap,,,,) =
            fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Approve
        vm.prank(contributor_);
        fundingPotToken.approve(address(fundingPot), amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundCapReached
                    .selector
            )
        );

        vm.prank(contributor_);
        fundingPot.contributeToRound(
            roundId,
            amount,
            accessId,
            address(fundingPotToken),
            new bytes32[](0)
        );
    }

    function testFuzzContributeToRound_revertsWhenContributionIsBeforeRoundStart(
    ) public {
        testCreateRound(1000);

        uint64 roundId = fundingPot.getRoundCount();
        uint8 accessId = 1;
        uint amount = 250;

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(0);

        fundingPot.setAccessCriteriaForRound(roundId, accessId, accessCriteria);

        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);

        // Approve
        vm.prank(contributor_);
        fundingPotToken.approve(address(fundingPot), 500);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundHasNotStarted
                    .selector
            )
        );

        vm.prank(contributor_);
        fundingPot.contributeToRound(
            roundId,
            amount,
            accessId,
            address(fundingPotToken),
            new bytes32[](0)
        );
    }

    function testFuzzContributeToRound_revertsWhenContributionIsAfterRoundEnd()
        public
    {
        testCreateRound(1000);

        uint64 roundId = fundingPot.getRoundCount();
        uint8 accessId = 1;
        uint amount = 250;

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(0);

        fundingPot.setAccessCriteriaForRound(roundId, accessId, accessCriteria);

        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 10 days);

        // Approve
        vm.prank(contributor_);
        fundingPotToken.approve(address(fundingPot), 500);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__RoundHasEnded
                    .selector
            )
        );

        vm.prank(contributor_);
        fundingPot.contributeToRound(
            roundId,
            amount,
            accessId,
            address(fundingPotToken),
            new bytes32[](0)
        );
    }

    function testFuzzContributeToRound_revertsWhenNFTAccessCriteriaIsNotMet()
        public
    {
        testCreateRound(1000);

        uint64 roundId = fundingPot.getRoundCount();
        uint8 accessId = 1;
        uint amount = 250;

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(1);

        fundingPot.setAccessCriteriaForRound(roundId, accessId, accessCriteria);

        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Approve
        vm.prank(contributor_);
        fundingPotToken.approve(address(fundingPot), amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__AccessCriteriaNftFailed
                    .selector
            )
        );

        vm.prank(contributor_);
        fundingPot.contributeToRound(
            roundId,
            amount,
            accessId,
            address(fundingPotToken),
            new bytes32[](0)
        );
    }

    function testFuzzContributeToRound_revertsWhenMerkleRootAccessCriteriaIsNotMet(
    ) public {
        testCreateRound(1000);

        uint64 roundId = fundingPot.getRoundCount();
        uint8 accessId = 1;
        uint amount = 250;

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(2);

        fundingPot.setAccessCriteriaForRound(roundId, accessId, accessCriteria);

        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Approve
        vm.prank(contributor_);
        fundingPotToken.approve(address(fundingPot), amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__AccessCriteriaMerkleFailed
                    .selector
            )
        );

        vm.prank(contributor_);
        fundingPot.contributeToRound(
            roundId, amount, accessId, address(fundingPotToken), PROOF
        );
    }

    function testFuzzContributeToRound_revertsWhenAllowedListAccessCriteriaIsNotMet(
    ) public {
        testCreateRound(1000);

        uint64 roundId = fundingPot.getRoundCount();
        uint8 accessId = 1;
        uint amount = 250;

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(3);

        fundingPot.setAccessCriteriaForRound(roundId, accessId, accessCriteria);

        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Approve
        vm.prank(contributor_);
        fundingPotToken.approve(address(fundingPot), amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__AccessCriteriaListFailed
                    .selector
            )
        );

        vm.prank(contributor_);
        fundingPot.contributeToRound(
            roundId,
            amount,
            accessId,
            address(fundingPotToken),
            new bytes32[](0)
        );
    }

    function testFuzzContributeToRound_revertsWhenContributionExceedsPersonalCap(
    ) public {
        testCreateRound(1000);

        uint64 roundId = fundingPot.getRoundCount();
        uint8 accessId = 1;
        uint amount = 250;

        ILM_PC_FundingPot_v1.AccessCriteria memory accessCriteria =
            _helper_createAccessCriteria(1);

        fundingPot.setAccessCriteriaForRound(roundId, accessId, accessCriteria);

        mockNFTContract.mint(contributor_);

        (uint roundStart,,,,,,) = fundingPot.getRoundGenericParameters(roundId);
        vm.warp(roundStart + 1);

        // Approve
        vm.prank(contributor_);
        fundingPotToken.approve(address(fundingPot), 500);

        vm.prank(contributor_);
        fundingPot.contributeToRound(
            roundId,
            amount,
            accessId,
            address(fundingPotToken),
            new bytes32[](0)
        );

        // Attempt to contribute beyond personal cap
        vm.expectRevert(
            abi.encodeWithSelector(
                ILM_PC_FundingPot_v1
                    .Module__LM_PC_FundingPot__PersonalCapReached
                    .selector
            )
        );
        vm.prank(contributor_);

        fundingPot.contributeToRound(
            roundId, 251, 0, address(fundingPotToken), new bytes32[](0)
        );
    }

    // -------------------------------------------------------------------------
    // Test: Internal Functions

    // -------------------------------------------------------------------------
    // Helper Functions

    // @notice Creates a default funding round
    function _helper_createDefaultFundingRound(uint roundCap_)
        internal
        returns (uint, uint, uint, address, bytes memory, bool, bool)
    {
        uint roundStart = block.timestamp + 1 days;
        uint roundEnd = block.timestamp + 2 days;
        uint roundCap = roundCap_;
        address hookContract = address(0);
        bytes memory hookFunction = bytes("");
        bool closureMechanism = false;
        bool globalAccumulativeCaps = false;

        return (
            roundStart,
            roundEnd,
            roundCap,
            hookContract,
            hookFunction,
            closureMechanism,
            globalAccumulativeCaps
        );
    }

    // @notice calls the create round function
    function _helper_callCreateRound(
        uint roundStart,
        uint roundEnd,
        uint roundCap,
        address hookContract,
        bytes memory hookFunction,
        bool closureMechanism,
        bool globalAccumulativeCaps
    ) internal {
        fundingPot.createRound(
            roundStart,
            roundEnd,
            roundCap,
            hookContract,
            hookFunction,
            closureMechanism,
            globalAccumulativeCaps
        );
    }

    // @notice Creates a predefined funding round with edited parameters for testing
    function _helper_createEditedRoundParams()
        internal
        returns (RoundParameters memory)
    {
        RoundParameters memory params;
        params.roundStart = block.timestamp + 3 days;
        params.roundEnd = block.timestamp + 4 days;
        params.roundCap = 2000;
        params.hookContract = address(0x1);
        params.hookFunction = bytes("test");
        params.closureMechanism = true;
        params.globalAccumulativeCaps = true;

        return params;
    }

    // @notice calls the create round function
    function _helper_callEditRound(
        uint64 roundId,
        RoundParameters memory params
    ) internal {
        fundingPot.editRound(
            roundId,
            params.roundStart,
            params.roundEnd,
            params.roundCap,
            params.hookContract,
            params.hookFunction,
            params.closureMechanism,
            params.globalAccumulativeCaps
        );
    }

    function _helper_createAccessCriteria(uint8 accessCriteriaEnum)
        internal
        returns (ILM_PC_FundingPot_v1.AccessCriteria memory)
    {
        {
            if (
                accessCriteriaEnum
                    == uint8(ILM_PC_FundingPot_v1.AccessCriteriaId.OPEN)
            ) {
                return ILM_PC_FundingPot_v1.AccessCriteria(
                    ILM_PC_FundingPot_v1.AccessCriteriaId.OPEN,
                    address(0x0),
                    bytes32(uint(0x0)),
                    new address[](0)
                );
            } else if (
                accessCriteriaEnum
                    == uint8(ILM_PC_FundingPot_v1.AccessCriteriaId.NFT)
            ) {
                address nftContract = address(mockNFTContract);

                return ILM_PC_FundingPot_v1.AccessCriteria(
                    ILM_PC_FundingPot_v1.AccessCriteriaId.NFT,
                    nftContract,
                    bytes32(uint(0x0)),
                    new address[](0)
                );
            } else if (
                accessCriteriaEnum
                    == uint8(ILM_PC_FundingPot_v1.AccessCriteriaId.MERKLE)
            ) {
                bytes32 merkleRoot = ROOT;

                return ILM_PC_FundingPot_v1.AccessCriteria(
                    ILM_PC_FundingPot_v1.AccessCriteriaId.MERKLE,
                    address(0x0),
                    merkleRoot,
                    new address[](0)
                );
            } else if (
                accessCriteriaEnum
                    == uint8(ILM_PC_FundingPot_v1.AccessCriteriaId.LIST)
            ) {
                address[] memory allowedAddresses = new address[](3);
                allowedAddresses[0] = address(0x1);
                allowedAddresses[1] = address(0x2);
                allowedAddresses[2] = address(0x3);

                return ILM_PC_FundingPot_v1.AccessCriteria(
                    ILM_PC_FundingPot_v1.AccessCriteriaId.LIST,
                    address(0x0),
                    bytes32(uint(0x0)),
                    allowedAddresses
                );
            }
        }
    }
}
