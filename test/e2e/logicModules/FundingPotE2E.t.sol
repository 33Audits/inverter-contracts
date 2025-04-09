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
import {FM_DepositVault_v1} from "@fm/depositVault/FM_DepositVault_v1.sol";
import {ERC165Upgradeable} from
    "@oz-up/utils/introspection/ERC165Upgradeable.sol";
import {ERC20Mock} from "test/utils/mocks/ERC20Mock.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";

contract FundingPotE2E is E2ETest {
    // Module Configurations for the current E2E test. Should be filled during setUp() call.
    IOrchestratorFactory_v1.ModuleConfig[] moduleConfigurations;

    // Let's create a list of contributors
    address contributor1 = makeAddr("contributor 1");
    address contributor2 = makeAddr("contributor 2");
    address contributor3 = makeAddr("contributor 3");

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

        // FundingManager
        setUpDepositVaultFundingManager();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                depositVaultMetadata, abi.encode(address(token))
            )
        );

        // Authorizer
        setUpRoleAuthorizer();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                roleAuthorizerMetadata, abi.encode(address(this))
            )
        );

        // PaymentProcessor
        setUpSimplePaymentProcessor();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                simplePaymentProcessorMetadata, bytes("")
            )
        );

        // Additional Logic Modules
        setUpLM_PC_FundingPot_v1();
        moduleConfigurations.push(
            IOrchestratorFactory_v1.ModuleConfig(
                LM_PC_FundingPot_v1Metadata, abi.encode(contributionToken)
            )
        );
    }

    function test_e2e_BountyManagerLifecycle() public {
        //--------------------------------------------------------------------------
        // Orchestrator_v1 Initialization
        //--------------------------------------------------------------------------
        IOrchestratorFactory_v1.WorkflowConfig memory workflowConfig =
        IOrchestratorFactory_v1.WorkflowConfig({
            independentUpdates: false,
            independentUpdateAdmin: address(0)
        });

        IOrchestrator_v1 orchestrator =
            _create_E2E_Orchestrator(workflowConfig, moduleConfigurations);

        FM_DepositVault_v1 fundingManager =
            FM_DepositVault_v1(address(orchestrator.fundingManager()));

        LM_PC_FundingPot_v1 fundingPot;

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

        // we authorize the deployer of the orchestrator as the fundngPot admin
        fundingPot.grantModuleRole(
            fundingPot.FUNDING_POT_ADMIN_ROLE(), address(this)
        );
        // Funders deposit funds

        // IMPORTANT
        // =========
        // Due to how the underlying rebase mechanism works, it is necessary
        // to always have some amount of tokens in the orchestrator.
        // It's best, if the owner deposits them right after deployment.
        uint initialDeposit = 10e18;
        token.mint(address(this), initialDeposit);
        token.approve(address(fundingManager), initialDeposit);
        fundingManager.deposit(initialDeposit);
    }
}
