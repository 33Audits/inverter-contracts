// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Dependencies
import {
    E2ETest,
    IOrchestratorFactory_v1,
    IOrchestrator_v1
} from "test/e2e/E2ETest.sol";

// SuT
import {
    LM_PC_FundingPot_v1,
    ILM_PC_FundingPot_v1
} from "@lm/LM_PC_FundingPot_v1.sol";
import {
    FM_BC_Bancor_Redeeming_VirtualSupply_v1,
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1
} from
    "test/modules/fundingManager/bondingCurve/FM_BC_Bancor_Redeeming_VirtualSupply_v1.t.sol";
import {PP_Streaming_v2} from "src/modules/paymentProcessor/PP_Streaming_v2.sol";
import {
    LM_PC_Bounties_v2, ILM_PC_Bounties_v2
} from "@lm/LM_PC_Bounties_v2.sol";

import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {ERC20Issuance_v1} from "@ex/token/ERC20Issuance_v1.sol";

contract FundingPotE2E is E2ETest {
    // Module Configurations for the current E2E test. Should be filled during setUp() call.
    IOrchestratorFactory_v1.ModuleConfig[] moduleConfigurations;

    // Let's create a list of contributors
    address contributor1 = makeAddr("contributor 1");
    address contributor2 = makeAddr("contributor 2");
    address contributor3 = makeAddr("contributor 3");
    ERC20Issuance_v1 issuanceToken;
    LM_PC_Bounties_v2 bountyManager;
    IOrchestrator_v1 orchestrator;
    IFM_BC_Bancor_Redeeming_VirtualSupply_v1 bondingCurveFundingManager;
    PP_Streaming_v2 paymentProcessor;
    LM_PC_FundingPot_v1 fundingPot;

    // Constants
    uint constant _SENTINEL = type(uint).max;
    ERC20Mock contributionToken = new ERC20Mock("Contribution Mock", "C_MOCK");

    function setUp() public override {
        vm.label({
            account: address(contributionToken),
            newLabel: ERC20Mock(address(contributionToken)).symbol()
        });
        // Setup common E2E framework
        super.setUp();

        // Set Up individual Modules the E2E test is going to use and store their configurations:
        // NOTE: It's important to store the module configurations in order, since _create_E2E_Orchestrator() will copy from the array.
        // The order should be:
        //      moduleConfigurations[0]  => FundingManager
        //      moduleConfigurations[1]  => Authorizer
        //      moduleConfigurations[2]  => PaymentProcessor
        //      moduleConfigurations[3:] => Additional Logic Modules

        // Authorizer
        setUpRoleAuthorizer();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                roleAuthorizerMetadata, abi.encode(address(this))
            )
        );

        // PaymentProcessor
        setUpStreamingPaymentProcessor();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                streamingPaymentProcessorMetadata,
                abi.encode(10, 0, 30) // defaultStart, defaultCliff, defaultEnd
            )
        );

        // Additional Logic Modules
        setUpLM_PC_FundingPot_v1();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                LM_PC_FundingPot_v1Metadata, abi.encode(contributionToken)
            )
        );
        setUpBancorVirtualSupplyBondingCurveFundingManager();

        // BancorFormula 'formula' is instantiated in the E2EModuleRegistry

        issuanceToken = new ERC20Issuance_v1(
            "Bonding Curve Token", "BCT", 18, type(uint).max - 1, address(this)
        );

        IFM_BC_Bancor_Redeeming_VirtualSupply_v1.BondingCurveProperties memory
            bc_properties = IFM_BC_Bancor_Redeeming_VirtualSupply_v1
                .BondingCurveProperties({
                formula: address(formula),
                reserveRatioForBuying: 333_333,
                reserveRatioForSelling: 333_333,
                buyFee: 0,
                sellFee: 0,
                buyIsOpen: true,
                sellIsOpen: true,
                initialIssuanceSupply: 10,
                initialCollateralSupply: 30
            });

        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                bancorVirtualSupplyBondingCurveFundingManagerMetadata,
                abi.encode(address(issuanceToken), bc_properties, token)
            )
        );
    }

    function init() private {
        //--------------------------------------------------------------------------
        // Orchestrator_v1 Initialization
        //--------------------------------------------------------------------------
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig =
        IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        orchestrator =
            _create_E2E_Orchestrator(workflowConfig, moduleConfigurations);

        // Get the Bancor bonding curve funding manager
        bondingCurveFundingManager = IFM_BC_Bancor_Redeeming_VirtualSupply_v1(
            address(orchestrator.fundingManager())
        );

        // Get the streaming payment processor
        paymentProcessor =
            PP_Streaming_v2(address(orchestrator.paymentProcessor()));

        // Get the funding pot
        address[] memory modulesList = orchestrator.listModules();
        for (uint i; i < modulesList.length; ++i) {
            if (
                ERC165Upgradeable(modulesList[i]).supportsInterface(
                    type(ILM_PC_FundingPot_v1).interfaceId
                )
            ) {
                fundingPot = LM_PC_FundingPot_v1(modulesList[i]);
                break;
            }
        }

        // Set up the bonding curve
        issuanceToken.setMinter(address(bondingCurveFundingManager), true);
    }

    function test_e2e_FundingPotLifecycle() public {
        init();

        // 2. Grant FUNDING_POT_ADMIN_ROLE to this contract for configuring rounds
        fundingPot.grantModuleRole(
            fundingPot.FUNDING_POT_ADMIN_ROLE(), address(this)
        );

        // Configure rounds
        // Round 1
        uint64 round1Id = fundingPot.createRound(
            block.timestamp + 1 days, // start
            block.timestamp + 30 days, // end
            1000e18, // cap
            address(0), // no hook
            bytes(""), // no hook function
            false, // auto closure
            false // no global caps
        );
        vm.warp(block.timestamp + 1 days);

        // Add access criteria to round 1
        address[] memory allowedAddresses = new address[](2);
        allowedAddresses[0] = contributor1;
        allowedAddresses[1] = contributor2;

        fundingPot.setAccessCriteriaForRound(
            round1Id,
            uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.LIST),
            address(0),
            bytes32(0),
            allowedAddresses
        );

        // Round 2
        uint64 round2Id = fundingPot.createRound(
            block.timestamp + 1, // start
            block.timestamp + 60 days, // end
            2e18, // cap
            address(0), // no hook
            bytes(""), // no hook function
            false, // auto closure
            false // no global caps
        );

        // Add access criteria to round 2
        allowedAddresses = new address[](1);
        allowedAddresses[0] = contributor3;

        fundingPot.setAccessCriteriaForRound(
            round2Id,
            uint8(ILM_PC_FundingPot_v1.AccessCriteriaType.LIST),
            address(0),
            bytes32(0),
            allowedAddresses
        );
        fundingPot.setAccessCriteriaPrivileges(
            round1Id,
            0, // accessCriteriaId
            1_000_000_000_000_000_000, // personalCap
            true, // overrideContributionSpan
            10, // start
            0, // cliff
            30 // end
        );
        fundingPot.setAccessCriteriaPrivileges(
            round2Id,
            0, // accessCriteriaId
            1_000_000_000_000_000_000, // personalCap
            true, // overrideContributionSpan
            10, // start
            0, // cliff
            30 // end
        );

        // Fund contributors
        contributionToken.mint(contributor1, 500e18);
        contributionToken.mint(contributor2, 500e18);
        contributionToken.mint(contributor3, 1000e18);

        // Contributors approve funding pot
        vm.prank(contributor1);
        contributionToken.approve(address(fundingPot), 500e18);
        vm.prank(contributor2);
        contributionToken.approve(address(fundingPot), 500e18);
        vm.prank(contributor3);
        contributionToken.approve(address(fundingPot), 1000e18);

        // Contributors contribute to rounds
        vm.prank(contributor1);
        fundingPot.contributeToRound(round1Id, 1e18, 0, new bytes32[](0));

        // Fast forward to after rounds end
        vm.warp(block.timestamp + 32 days);

        //// TODO: Zuhaib
        //// rebase onto your other branch
        //// first get this to compile
        /// once it compiles we shoule be able to check that the PP streaming has a order created
        /// for contributor1
        /// We should then be able to process payments
        /// and these tokesn will get sent to contributor1

        /// Assert a payment order was created
        PP_Streaming_v2.Stream[] memory streams = paymentProcessor
            .viewAllPaymentOrders(address(fundingPot), contributor1);
        assertEq(streams.length, 1);

        // Verify tokens were minted from curve
        uint totalContributions = 1500e18; // 300 + 200 + 1000
    }
}
