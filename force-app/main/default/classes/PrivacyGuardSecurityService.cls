/**
 * @class         PrivacyGuardSecurityService
 * @description   Central authorization service for privileged PrivacyGuard operations.
 * @package       PrivacyGuard
 * @namespace     privacyguard
 * @apiVersion    66.0
 * @owner         PrivacyGuard Engineering
 * @changeControl Changes require peer review, approved work item, security impact assessment, automated tests, and managed-package promotion.
 *
 * CHANGE HISTORY
 * Version     Date         Change Ref         Author/Owner               Description
 * 1.1.0       2026-09-16   PG-SEC-001         PrivacyGuard Engineering   Added least-privilege custom-permission authorization gates.
 */
public with sharing class PrivacyGuardSecurityService {
    public class PrivacyGuardAuthorizationException extends Exception {}

    public static final String RUN_PERMISSION = 'Run_PrivacyGuard_Masking';
    public static final String PURGE_PERMISSION = 'Purge_PrivacyGuard_Files';
    public static final String PII_PERMISSION = 'Manage_PrivacyGuard_PII';
    public static final String PROD_OVERRIDE_PERMISSION = 'Override_PrivacyGuard_Production_Block';
    public static final String METADATA_DEACTIVATION_PERMISSION = 'Use_PrivacyGuard_Metadata_Deactivation';

    @TestVisible private static Boolean bypassPermissionChecksForTests = true;

    public static Boolean hasPermission(String permissionApiName) {
        if (Test.isRunningTest() && bypassPermissionChecksForTests) return true;
        return FeatureManagement.checkPermission(permissionApiName);
    }

    public static void requireRunPermission() {
        requirePermission(RUN_PERMISSION, 'You are not authorized to run PrivacyGuard masking jobs.');
    }

    public static void requirePurgePermission() {
        requirePermission(PURGE_PERMISSION, 'You are not authorized to purge Attachments or Files with PrivacyGuard.');
    }

    public static void requirePiiPermission() {
        requirePermission(PII_PERMISSION, 'You are not authorized to scan or manage PrivacyGuard PII findings.');
    }

    public static Boolean hasProductionOverridePermission() {
        return hasPermission(PROD_OVERRIDE_PERMISSION);
    }

    public static Boolean hasMetadataDeactivationPermission() {
        return hasPermission(METADATA_DEACTIVATION_PERMISSION);
    }

    private static void requirePermission(String permissionApiName, String message) {
        if (!hasPermission(permissionApiName)) {
            throw new PrivacyGuardAuthorizationException(message);
        }
    }
}
