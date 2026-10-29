/**
 * @class         EnvironmentSafetyServiceTest
 * @description   Apex test class for the PrivacyGuard managed package. See the implementation comments below for functional and security design details.
 * @package       PrivacyGuard
 * @namespace     privacyguard
 * @apiVersion    66.0
 * @owner         PrivacyGuard Engineering
 * @changeControl Changes to this class must be peer reviewed, linked to an approved work item, validated by automated tests, and promoted through the managed-package release process.
 *
 * CHANGE HISTORY
 * Version     Date         Change Ref         Author/Owner               Description
 * 1.0.0       2026-09-16   PG-BASELINE-001    PrivacyGuard Engineering   Established managed-package audit and change-control baseline.
 */
@isTest
private with sharing class EnvironmentSafetyServiceTest {

    @testSetup
    static void setup() {
        MaskingTestConfiguration.createDefaults();
        insert new Contact(LastName = 'OriginalLastName', Email = 'original@example.com', Phone = '415-555-0100');
    }

    @isTest
    static void testExecutionBlockedWhenNotSandboxAndNoOverride() {
        EnvironmentSafetyService.sandboxOverrideForTests = false;

        Boolean threw = false;
        Test.startTest();
        try {
            EnvironmentSafetyService.assertExecutionAllowed();
        } catch (EnvironmentSafetyService.ProductionExecutionBlockedException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Expected execution to be blocked outside of a Sandbox with no override set');

        Contact unchanged = [SELECT LastName FROM Contact LIMIT 1];
        System.assertEquals('OriginalLastName', unchanged.LastName, 'No masking should have occurred');
    }

    @isTest
    static void testExecutionAllowedWhenSandbox() {
        EnvironmentSafetyService.sandboxOverrideForTests = true;

        System.assertEquals(true, EnvironmentSafetyService.isExecutionAllowed(),
            'The safety gate must allow execution when treated as a sandbox.');
        EnvironmentSafetyService.assertExecutionAllowed();
    }

    @isTest
    static void testExecutionBlockedInNonSandboxWithFormerOverrideEnabled() {
        EnvironmentSafetyService.sandboxOverrideForTests = false;

        Masking_Environment_Override__c settings = Masking_Environment_Override__c.getOrgDefaults();
        if (settings.Id == null) settings = new Masking_Environment_Override__c();
        settings.Allow_Run_In_Production__c = true;
        upsert settings;

        System.assertEquals(true, PrivacyGuardSecurityService.hasProductionOverridePermission(),
            'This test exercises the former permission and setting together.');
        System.assertEquals(false, EnvironmentSafetyService.isExecutionAllowed());
        Boolean blocked = false;
        try { EnvironmentSafetyService.assertExecutionAllowed(); }
        catch (EnvironmentSafetyService.ProductionExecutionBlockedException e) { blocked = true; }
        System.assert(blocked, 'The former override must no longer permit production execution.');

        Contact updated = [SELECT LastName FROM Contact LIMIT 1];
        System.assertEquals('OriginalLastName', updated.LastName,
            'Production data must remain unchanged even when the former setting is enabled');
    }

    @isTest
    static void testPurgeAndRecoveryBlockedWithFormerOverride() {
        EnvironmentSafetyService.sandboxOverrideForTests = false;
        upsert new Masking_Environment_Override__c(
            SetupOwnerId = UserInfo.getOrganizationId(), Allow_Run_In_Production__c = true);
        Boolean purgeBlocked = false;
        try {
            new FileAttachmentDeletionBatch('test', 'Contact', FileAttachmentDeletionBatch.MODE_ATTACHMENTS).start(null);
        } catch (EnvironmentSafetyService.ProductionExecutionBlockedException e) { purgeBlocked = true; }
        Boolean recoveryBlocked = false;
        try {
            new MaskingFailedRecordRecoveryBatch('test', 'Contact', null, 'Full', null, null, null, null).start(null);
        } catch (EnvironmentSafetyService.ProductionExecutionBlockedException e) { recoveryBlocked = true; }
        System.assert(purgeBlocked, 'File deletion must remain blocked outside sandboxes.');
        System.assert(recoveryBlocked, 'Masking recovery must remain blocked outside sandboxes.');
    }

    @isTest
    static void testDirectBatchInvocationIsAlsoBlocked() {
        EnvironmentSafetyService.sandboxOverrideForTests = false;

        List<MaskingConfigService.FieldConfig> fields = MaskingConfigService.getActiveFieldConfigsByObject().get('Contact');

        Boolean threw = false;
        try {
            new MaskingBatch('Direct_Invoke_Test', 'Contact', fields).start(null);
        } catch (EnvironmentSafetyService.ProductionExecutionBlockedException e) {
            threw = true;
        }

        System.assert(threw, 'Directly invoking MaskingBatch should still be blocked outside a Sandbox');
    }
}
