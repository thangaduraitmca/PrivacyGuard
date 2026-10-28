/**
 * @class         AutomationMetadataToggleService
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
 * Actually deactivates/reactivates Flows (Process Builders are Flows under the hood,
 * so this covers both) and Validation Rules via the Tooling API - not just flipping a
 * bypass flag. Apex Triggers are deliberately NOT covered here: toggling a trigger's
 * status via the Tooling API requires an asynchronous compile step
 * (MetadataContainer + ApexTriggerMember + ContainerAsyncRequest) that this framework
 * doesn't attempt, since it can't complete synchronously within a single transaction
 * and would need its own polling mechanism to do reliably. Triggers continue to rely
 * on Bypass_Triggers__c being checked in trigger code (see AutomationManagerService).
 *
 * IMPORTANT CAVEATS - read before enabling Use_Metadata_Deactivation__c:
 * - Deactivating a Flow affects EVERY use of it, including Screen Flows a user might
 *   be actively running - during the masking window, users temporarily cannot launch
 *   any Flow in the org, not just record-triggered ones.
 * - Each component is one HTTP callout (query is separate). Apex allows 100 callouts
 *   per transaction; this stops after MAX_CALLOUTS_PER_RUN to stay well under that
 *   limit (leaving headroom for other callouts in the same run) and logs a warning if
 *   an org has more active Flows/Validation Rules than that - the bypass-flag
 *   mechanism remains the fallback safety net for anything not reached.
 * - Every failure here is caught and logged rather than thrown - if the Tooling API
 *   call fails entirely (e.g. missing Remote Site Setting), the masking run still
 *   proceeds protected by the bypass flags alone.
 * - This has not been validated against a live org from this environment. Test
 *   against a small, non-critical set of automations in a sandbox before relying on
 *   it broadly.
 */
public with sharing class AutomationMetadataToggleService {

    private static final Integer MAX_CALLOUTS_PER_RUN = 80;

    public static Integer deactivateAllFlowsAndValidationRules(String runId) {
        Integer calloutsUsed = 0;
        Integer deactivatedCount = 0;

        DeactivationResult flowResult = deactivateFlows(runId, MAX_CALLOUTS_PER_RUN - calloutsUsed);
        calloutsUsed += flowResult.calloutsUsed;
        deactivatedCount += flowResult.successCount;

        DeactivationResult vrResult = deactivateValidationRules(runId, MAX_CALLOUTS_PER_RUN - calloutsUsed);
        calloutsUsed += vrResult.calloutsUsed;
        deactivatedCount += vrResult.successCount;

        return deactivatedCount;
    }

    public static Integer reactivateAll(String runId) {
        Integer count = 0;
        count += reactivateFlows(runId);
        count += reactivateValidationRules(runId);
        return count;
    }

    private class DeactivationResult {
        Integer successCount = 0;
        Integer calloutsUsed = 0;
    }

    private static DeactivationResult deactivateFlows(String runId, Integer calloutBudget) {
        DeactivationResult result = new DeactivationResult();
        if (calloutBudget <= 0) return result;

        try {
            Map<String, Object> queryResult = ToolingApiClient.query(
                'SELECT Id, DeveloperName, ActiveVersion.VersionNumber FROM FlowDefinition WHERE ActiveVersionId != null'
            );
            result.calloutsUsed++;

            List<Object> records = (List<Object>) queryResult.get('records');
            List<Deactivated_Automation__c> toInsert = new List<Deactivated_Automation__c>();

            for (Object recObj : records) {
                if (result.calloutsUsed >= calloutBudget) {
                    MaskingLogger.logInfo('AutomationMetadataToggleService',
                        'Reached the per-run callout budget deactivating Flows - remaining active Flows were left as-is; relying on Bypass_Flows__c for those.');
                    break;
                }

                Map<String, Object> rec = (Map<String, Object>) recObj;
                String id = (String) rec.get('Id');
                String devName = (String) rec.get('DeveloperName');
                Map<String, Object> activeVersion = (Map<String, Object>) rec.get('ActiveVersion');
                Integer versionNumber = (activeVersion != null) ? (Integer) activeVersion.get('VersionNumber') : null;

                try {
                    ToolingApiClient.patch('FlowDefinition', id, '{"Metadata":{"activeVersionNumber":null}}');
                    result.calloutsUsed++;
                    toInsert.add(new Deactivated_Automation__c(
                        Run_Id__c = runId,
                        Component_Type__c = 'FLOW',
                        Component_Id__c = id,
                        Component_Name__c = devName,
                        Original_State_Json__c = versionNumber != null ? String.valueOf(versionNumber) : null,
                        Reactivated__c = false
                    ));
                    result.successCount++;
                } catch (Exception e) {
                    result.calloutsUsed++;
                    MaskingLogger.logError('AutomationMetadataToggleService', 'FlowDefinition', null, devName,
                        'Could not deactivate Flow ' + devName + ': ' + e.getMessage());
                }
            }

            if (!toInsert.isEmpty()) insert toInsert;
        } catch (Exception e) {
            MaskingLogger.logInfo('AutomationMetadataToggleService',
                'Could not query Flows via Tooling API - skipping Flow deactivation, relying on Bypass_Flows__c instead: ' + e.getMessage());
        }
        return result;
    }

    private static Integer reactivateFlows(String runId) {
        Integer count = 0;
        for (Deactivated_Automation__c rec : [
            SELECT Id, Component_Id__c, Component_Name__c, Original_State_Json__c
            FROM Deactivated_Automation__c
            WHERE Run_Id__c = :runId AND Component_Type__c = 'FLOW' AND Reactivated__c = false
        ]) {
            try {
                if (String.isBlank(rec.Original_State_Json__c)) {
                    MaskingLogger.logError('AutomationMetadataToggleService', 'FlowDefinition', null, rec.Component_Name__c,
                        'No original version number recorded for ' + rec.Component_Name__c + ' - cannot auto-reactivate; re-activate manually in Setup.');
                    continue;
                }
                ToolingApiClient.patch('FlowDefinition', rec.Component_Id__c,
                    '{"Metadata":{"activeVersionNumber":' + rec.Original_State_Json__c + '}}');
                markReactivated(rec.Id);
                count++;
            } catch (Exception e) {
                MaskingLogger.logError('AutomationMetadataToggleService', 'FlowDefinition', null, rec.Component_Name__c,
                    'Could not reactivate Flow ' + rec.Component_Name__c + ': ' + e.getMessage());
            }
        }
        return count;
    }

    private static DeactivationResult deactivateValidationRules(String runId, Integer calloutBudget) {
        DeactivationResult result = new DeactivationResult();
        if (calloutBudget <= 0) return result;

        try {
            Map<String, Object> queryResult = ToolingApiClient.query(
                'SELECT Id, ValidationName FROM ValidationRule WHERE Active = true'
            );
            result.calloutsUsed++;

            List<Object> records = (List<Object>) queryResult.get('records');
            List<Deactivated_Automation__c> toInsert = new List<Deactivated_Automation__c>();

            for (Object recObj : records) {
                if (result.calloutsUsed >= calloutBudget) {
                    MaskingLogger.logInfo('AutomationMetadataToggleService',
                        'Reached the per-run callout budget deactivating Validation Rules - remaining active rules were left as-is; relying on Bypass_Validation_Rules__c for those.');
                    break;
                }

                Map<String, Object> rec = (Map<String, Object>) recObj;
                String id = (String) rec.get('Id');
                String name = (String) rec.get('ValidationName');

                try {
                    ToolingApiClient.patch('ValidationRule', id, '{"Metadata":{"active":false}}');
                    result.calloutsUsed++;
                    toInsert.add(new Deactivated_Automation__c(
                        Run_Id__c = runId,
                        Component_Type__c = 'VALIDATION_RULE',
                        Component_Id__c = id,
                        Component_Name__c = name,
                        Reactivated__c = false
                    ));
                    result.successCount++;
                } catch (Exception e) {
                    result.calloutsUsed++;
                    MaskingLogger.logError('AutomationMetadataToggleService', 'ValidationRule', null, name,
                        'Could not deactivate Validation Rule ' + name + ': ' + e.getMessage());
                }
            }

            if (!toInsert.isEmpty()) insert toInsert;
        } catch (Exception e) {
            MaskingLogger.logInfo('AutomationMetadataToggleService',
                'Could not query Validation Rules via Tooling API - skipping, relying on Bypass_Validation_Rules__c instead: ' + e.getMessage());
        }
        return result;
    }

    private static Integer reactivateValidationRules(String runId) {
        Integer count = 0;
        for (Deactivated_Automation__c rec : [
            SELECT Id, Component_Id__c, Component_Name__c
            FROM Deactivated_Automation__c
            WHERE Run_Id__c = :runId AND Component_Type__c = 'VALIDATION_RULE' AND Reactivated__c = false
        ]) {
            try {
                ToolingApiClient.patch('ValidationRule', rec.Component_Id__c, '{"Metadata":{"active":true}}');
                markReactivated(rec.Id);
                count++;
            } catch (Exception e) {
                MaskingLogger.logError('AutomationMetadataToggleService', 'ValidationRule', null, rec.Component_Name__c,
                    'Could not reactivate Validation Rule ' + rec.Component_Name__c + ': ' + e.getMessage());
            }
        }
        return count;
    }

    private static void markReactivated(Id recordId) {
        update new Deactivated_Automation__c(Id = recordId, Reactivated__c = true, Reactivated_Date__c = System.now());
    }
}
