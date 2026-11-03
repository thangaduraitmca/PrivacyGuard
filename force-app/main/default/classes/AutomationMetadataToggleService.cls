/**
 * Compatibility entry points for retired Flow and Validation Rule metadata changes.
 * PrivacyGuard supports Apex trigger metadata management only. These methods fail
 * before making callouts or changing tracking records, including restoration.
 * Restore any legacy Flow/Validation Rule changes manually in Salesforce Setup.
 */
public with sharing class AutomationMetadataToggleService {
    public class UnsupportedAutomationException extends Exception {}

    public static Integer deactivateAllFlowsAndValidationRules(String runId) {
        throw new UnsupportedAutomationException(
            'Flow and Validation Rule metadata changes are not supported. Use Apex trigger management only.');
    }

    public static Integer reactivateAll(String runId) {
        throw new UnsupportedAutomationException(
            'Legacy Flow and Validation Rule restoration requires manual review in Salesforce Setup.');
    }
}
