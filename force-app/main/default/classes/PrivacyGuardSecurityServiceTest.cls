/**
 * @class         PrivacyGuardSecurityServiceTest
 * @description   Authorization-gate tests for PrivacyGuard privileged operations.
 * @package       PrivacyGuard
 * @namespace     privacyguard
 * @apiVersion    66.0
 * @owner         PrivacyGuard Engineering
 * @changeControl Changes require peer review and an approved security work item.
 *
 * CHANGE HISTORY
 * Version     Date         Change Ref         Author/Owner               Description
 * 1.1.0       2026-09-16   PG-SEC-001         PrivacyGuard Engineering   Initial authorization service tests.
 */
@IsTest
private class PrivacyGuardSecurityServiceTest {
    @IsTest static void testKnownPermissionConstantsAreDefined() {
        System.assertEquals('Run_PrivacyGuard_Masking', PrivacyGuardSecurityService.RUN_PERMISSION);
        System.assertEquals('Purge_PrivacyGuard_Files', PrivacyGuardSecurityService.PURGE_PERMISSION);
        System.assertEquals('Manage_PrivacyGuard_PII', PrivacyGuardSecurityService.PII_PERMISSION);
        System.assertEquals('Override_PrivacyGuard_Production_Block', PrivacyGuardSecurityService.PROD_OVERRIDE_PERMISSION);
        System.assertEquals('Use_PrivacyGuard_Metadata_Deactivation', PrivacyGuardSecurityService.METADATA_DEACTIVATION_PERMISSION);
    }

    @IsTest static void testAuthorizationMethodsAreCallableInTestContext() {
        PrivacyGuardSecurityService.requireRunPermission();
        PrivacyGuardSecurityService.requirePurgePermission();
        PrivacyGuardSecurityService.requirePiiPermission();
        System.assertEquals(true, PrivacyGuardSecurityService.hasProductionOverridePermission());
        System.assertEquals(true, PrivacyGuardSecurityService.hasMetadataDeactivationPermission());
    }
}
