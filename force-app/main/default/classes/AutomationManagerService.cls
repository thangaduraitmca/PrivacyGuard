/**
 * @class         AutomationManagerService
 * @description   Apex class for the PrivacyGuard managed package. See the implementation comments below for functional and security design details.
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
/**
 * Controls the Automation_Bypass__c hierarchy custom setting, and optionally drives
 * real Tooling API deactivation of Flows/Validation Rules via
 * AutomationMetadataToggleService.
 *
 * TWO LAYERS OF PROTECTION, always both active:
 * 1. Bypass flags (always applied) - the standard "bypass switch" pattern, because
 *    Apex can't flip a Flow's/Trigger's/Validation Rule's active status synchronously
 *    at runtime by default. Your Flows, Triggers, and Validation Rules must be built
 *    to check these flags and exit early when true:
 *      - Flow: add a Decision element checking {!$Setup.Automation_Bypass__c.Bypass_Flows__c}
 *      - Trigger: guard the trigger body with
 *          if (Automation_Bypass__c.getInstance().Bypass_Triggers__c) return;
 *      - Validation Rule: wrap your rule logic in
 *          AND(NOT($Setup.Automation_Bypass__c.Bypass_Validation_Rules__c), ...)
 *    This is the ONLY protection for Apex Triggers - see AutomationMetadataToggleService
 *    for why triggers aren't included in layer 2.
 * 2. Real deactivation (opt-in via Automation_Bypass__c.Use_Metadata_Deactivation__c) -
 *    actually queries and deactivates every active Flow and Validation Rule via the
 *    Tooling API, then reactivates the same ones afterward. Useful for orgs where
 *    automations haven't been retrofitted with the bypass-flag checks above. See
 *    AutomationMetadataToggleService for prerequisites and important caveats before
 *    enabling this - it needs a Remote Site Setting and has callout-volume limits.
 */
public with sharing class AutomationManagerService {

    public static void disableAllAutomations() {
        Automation_Bypass__c settings = getSettingsForUpdate();
        settings.Bypass_All_Automations__c = true;
        settings.Bypass_Triggers__c = true;
        settings.Bypass_Flows__c = true;
        settings.Bypass_Validation_Rules__c = true;
        upsert settings;
        MaskingLogger.logInfo('AutomationManagerService', 'Bypass flags enabled before masking run.');

        if (settings.Use_Metadata_Deactivation__c == true) {
            if (!PrivacyGuardSecurityService.hasMetadataDeactivationPermission()) {
                throw new PrivacyGuardSecurityService.PrivacyGuardAuthorizationException(
                    'Metadata deactivation is enabled in configuration, but the running user does not have the highly privileged Use PrivacyGuard Metadata Deactivation permission.');
            }
            String runId = generateRunId();
            storeRunId(runId);
            try {
                Integer count = AutomationMetadataToggleService.deactivateAllFlowsAndValidationRules(runId);
                MaskingLogger.logInfo('AutomationManagerService',
                    'Metadata deactivation: ' + count + ' Flow(s)/Validation Rule(s) actually deactivated via Tooling API for run ' + runId + '.');
            } catch (Exception e) {
                MaskingLogger.logInfo('AutomationManagerService',
                    'Metadata deactivation via Tooling API failed - continuing with bypass-flag-only protection: ' + e.getMessage());
            }
        }
    }

    public static void enableAllAutomations() {
        Automation_Bypass__c settings = getSettingsForUpdate();

        if (settings.Use_Metadata_Deactivation__c == true) {
            String runId = getStoredRunId();
            if (String.isNotBlank(runId)) {
                try {
                    Integer count = AutomationMetadataToggleService.reactivateAll(runId);
                    MaskingLogger.logInfo('AutomationManagerService',
                        'Metadata reactivation: ' + count + ' Flow(s)/Validation Rule(s) reactivated via Tooling API for run ' + runId + '.');
                } catch (Exception e) {
                    MaskingLogger.logInfo('AutomationManagerService',
                        'Metadata reactivation via Tooling API failed: ' + e.getMessage() +
                        '. Check the Deactivated Automation tab and reactivate any remaining components manually in Setup.');
                }
            }
        }

        settings.Bypass_All_Automations__c = false;
        settings.Bypass_Triggers__c = false;
        settings.Bypass_Flows__c = false;
        settings.Bypass_Validation_Rules__c = false;
        upsert settings;
        MaskingLogger.logInfo('AutomationManagerService', 'Bypass flags cleared after masking run.');
    }

    private static Automation_Bypass__c getSettingsForUpdate() {
        Automation_Bypass__c settings = Automation_Bypass__c.getOrgDefaults();
        if (settings.Id == null) {
            settings = new Automation_Bypass__c();
        }
        return settings;
    }

    private static String generateRunId() {
        return String.valueOf(Datetime.now().getTime()) + '-' + String.valueOf(Math.abs(Crypto.getRandomInteger()));
    }

    private static void storeRunId(String runId) {
        Masking_Run_Tracker__c tracker = Masking_Run_Tracker__c.getOrgDefaults();
        if (tracker.Id == null) tracker = new Masking_Run_Tracker__c();
        tracker.Current_Run_Id__c = runId;
        upsert tracker;
    }

    private static String getStoredRunId() {
        Masking_Run_Tracker__c tracker = Masking_Run_Tracker__c.getOrgDefaults();
        return tracker.Id != null ? tracker.Current_Run_Id__c : null;
    }
}
