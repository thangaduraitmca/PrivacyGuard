/** Persistent, serialized ownership of cooperative automation bypass flags.
 * Does not change trigger/Flow/validation-rule metadata. Subscriber automation
 * must explicitly consult these flags. Internal state uses system mode only
 * after the masking permission and sandbox gates have passed.
 */
public with sharing class AutomationManagerService {
    public class BypassStateException extends Exception {}
    private static final String LEGACY_OWNER = 'PrivacyGuard.LegacyOrchestrator';
    private static final List<String> FLAGS = new List<String>{
        'Bypass_All_Automations__c', 'Bypass_Triggers__c',
        'Bypass_Flows__c', 'Bypass_Validation_Rules__c'
    };

    public static void disableAllAutomations() { disableAllAutomations(LEGACY_OWNER); }
    public static void enableAllAutomations() { enableAllAutomations(LEGACY_OWNER); }

    public static void disableAllAutomations(String owner) {
        authorize();
        validateOwner(owner);
        Automation_Bypass__c settings = lockSettings();
        if (String.isNotBlank(settings.Bypass_Owner__c)) {
            throw new BypassStateException('Another PrivacyGuard run owns the automation bypass. Finish or recover that run before starting another.');
        }
        // The former opt-in delegates to retired methods and never worked.
        // Reject before any flag/snapshot mutation rather than silently continue.
        if (settings.Use_Metadata_Deactivation__c == true) {
            throw new BypassStateException('Flow/validation-rule metadata deactivation is retired. Disable Use Metadata Deactivation and use Apex trigger management separately.');
        }
        Map<String, Boolean> original = new Map<String, Boolean>();
        for (String field : FLAGS) {
            original.put(field, (Boolean)settings.get(field) == true);
            settings.put(field, true);
        }
        settings.Bypass_Snapshot__c = JSON.serialize(original);
        settings.Bypass_Owner__c = owner;
        update as system settings;
    }

    public static void enableAllAutomations(String owner) {
        authorize();
        validateOwner(owner);
        Automation_Bypass__c settings = lockSettings();
        // Duplicate completion and calls predating this patch must never clear flags.
        if (String.isBlank(settings.Bypass_Owner__c)) return;
        if (settings.Bypass_Owner__c != owner) {
            throw new BypassStateException('This run does not own the automation bypass; no flags were restored.');
        }
        Map<String, Object> original;
        try {
            original = (Map<String, Object>)JSON.deserializeUntyped(settings.Bypass_Snapshot__c);
            for (String field : FLAGS) {
                if (original == null || !original.containsKey(field) || !(original.get(field) instanceof Boolean)) {
                    throw new BypassStateException('Invalid snapshot.');
                }
            }
        } catch (Exception e) {
            throw new BypassStateException('Automation bypass snapshot is missing or invalid. State retained for administrator recovery.');
        }
        for (String field : FLAGS) {
            // false differs from the true applied by us: preserve that admin edit.
            if ((Boolean)settings.get(field) == true) settings.put(field, original.get(field));
        }
        settings.Bypass_Snapshot__c = null;
        settings.Bypass_Owner__c = null;
        update as system settings;
    }

    private static Automation_Bypass__c lockSettings() {
        Id orgId = UserInfo.getOrganizationId();
        List<Automation_Bypass__c> rows = [
            SELECT Id, Bypass_All_Automations__c, Bypass_Triggers__c,
                Bypass_Flows__c, Bypass_Validation_Rules__c,
                Use_Metadata_Deactivation__c, Bypass_Owner__c, Bypass_Snapshot__c
            FROM Automation_Bypass__c WHERE SetupOwnerId = :orgId FOR UPDATE
        ];
        if (!rows.isEmpty()) return rows[0];
        Automation_Bypass__c created = new Automation_Bypass__c(SetupOwnerId = orgId);
        // SetupOwnerId is unique for this hierarchy setting. Concurrent first
        // inserts cannot both succeed; the loser fails before bypass changes.
        insert as system created;
        return created;
    }
    private static void authorize() {
        PrivacyGuardSecurityService.requireRunPermission();
        EnvironmentSafetyService.assertExecutionAllowed();
    }
    private static void validateOwner(String owner) {
        if (String.isBlank(owner) || owner.length() > 80) throw new BypassStateException('A valid bypass owner is required.');
    }
}
