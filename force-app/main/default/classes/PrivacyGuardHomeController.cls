/** PrivacyGuard dashboard. Configuration and execution indicators are not compliance certification. */
public with sharing class PrivacyGuardHomeController {
    @AuraEnabled(cacheable=true)
    public static Overview getOverview() {
        PrivacyGuardSecurityService.requirePiiPermission();
        Overview result = new Overview();
        result.environmentName = [SELECT Name FROM Organization WITH USER_MODE LIMIT 1].Name;
        result.acceptedFields = 0;
        result.protectedFields = 0;
        result.reviewFields = 0;
        result.objectsConfigured = 0;
        result.fieldsConfigured = 0;
        result.completedRuns = 0;
        result.failedRuns = 0;
        result.coverage = 0;
        result.privacyStatus = 'Not Assessed';
        result.privacyExplanation = 'A completed masking job and reviewed PII configuration are required before protection can be evaluated.';
        result.recentRuns = new List<RunRow>();

        // PII scan information is optional for configuration metrics. A missing or
        // inaccessible scan field must not hide otherwise valid masking configurations.
        Set<String> acceptedKeys = new Set<String>();
        Set<String> pendingKeys = new Set<String>();
        // Multiple scans can contain the same field. Use the newest review state.
        Set<String> reviewedKeys = new Set<String>();
        Boolean scanAvailable = true;
        try {
            // Static references are namespace-aware in managed packages and avoid
            // constructing SOQL identifiers from describe-map aliases.
            for (PII_Scan_Result__c row : [
                SELECT Object_API_Name__c, Field_API_Name__c, Review_Status__c
                FROM PII_Scan_Result__c WITH USER_MODE
                ORDER BY CreatedDate DESC, Id DESC LIMIT 50000
            ]) {
                String key = coverageKey(row.Object_API_Name__c, row.Field_API_Name__c);
                if (key == null || reviewedKeys.contains(key)) continue;
                reviewedKeys.add(key);
                String status = row.Review_Status__c;
                if (status == 'Accepted') acceptedKeys.add(key);
                else if (status == 'New') pendingKeys.add(key);
            }
            result.acceptedFields = acceptedKeys.size();
            result.reviewFields = pendingKeys.size();
        } catch (Exception ex) {
            scanAvailable = false;
            result.acceptedFields = null;
            result.reviewFields = null;
            result.dataWarning = 'PII scan metrics are unavailable. Verify PII Scan Result field metadata and permissions. Masking configuration metrics remain available.';
            System.debug(LoggingLevel.WARN, 'PrivacyGuard dashboard PII scan query failed: ' + ex.getMessage());
        }

        Set<String> configuredKeys = new Set<String>();
        Set<String> configuredObjects = new Set<String>();
        for (Masking_Field_Config__c row : [
            SELECT Object_API_Name__c, Field_API_Name__c FROM Masking_Field_Config__c
            WHERE Is_Active__c = true WITH USER_MODE LIMIT 50000
        ]) {
            String objectApi = row.Object_API_Name__c;
            String key = coverageKey(objectApi, row.Field_API_Name__c);
            if (key == null) continue;
            configuredKeys.add(key);
            configuredObjects.add(objectApi.trim().toLowerCase());
        }
        result.objectsConfigured = configuredObjects.size();
        result.fieldsConfigured = configuredKeys.size();
        for (String key : acceptedKeys) {
            if (configuredKeys.contains(key)) result.protectedFields++;
        }
        if (scanAvailable && result.acceptedFields > 0) result.coverage = (Integer)Math.round(100.0 * result.protectedFields / result.acceptedFields);
        if (!scanAvailable) { result.protectedFields = null; result.coverage = null; }

        Boolean runsAvailable = true;
        try {
            // Aggregate every visible run; do not derive totals from the recent list.
            for (AggregateResult aggregateRow : [
                SELECT Status__c runStatus, COUNT(Id) runCount FROM Masking_Job_Run__c
                WITH USER_MODE GROUP BY Status__c
            ]) {
                String status = String.valueOf(aggregateRow.get('runStatus'));
                Integer count = (Integer)aggregateRow.get('runCount');
                if (status == 'Completed') result.completedRuns += count;
                if (status == 'Failed' || status == 'Completed with Errors') result.failedRuns += count;
            }
            // Recent-run list is independent of the aggregate totals.
            for (Masking_Job_Run__c job : [
                SELECT Id, Name, Status__c, Started_At__c FROM Masking_Job_Run__c
                WITH USER_MODE ORDER BY CreatedDate DESC LIMIT 5
            ]) {
                RunRow row = new RunRow();
                row.id = job.Id;
                row.name = job.Name;
                row.status = job.Status__c;
                Datetime started = job.Started_At__c;
                row.started = started == null ? 'Date unavailable' : started.format();
                result.recentRuns.add(row);
            }
        } catch (Exception runEx) {
            runsAvailable = false;
            result.completedRuns = null;
            result.failedRuns = null;
            result.recentRuns.clear();
            String runWarning = 'Masking run metrics are unavailable. Check Masking Job Run object access, Status and Started At field read permissions, and Apex debug logs.';
            result.dataWarning = String.isBlank(result.dataWarning) ? runWarning : result.dataWarning + ' ' + runWarning;
            System.debug(LoggingLevel.ERROR, 'PrivacyGuard dashboard run query failed (' + runEx.getTypeName() + '): ' + runEx.getMessage());
        }
        if (!scanAvailable || !runsAvailable) {
            result.privacyStatus = 'Not Assessed';
            result.privacyExplanation = 'PII scan or masking run information is unavailable; protection cannot be assessed.';
        } else if (result.failedRuns > 0 || result.reviewFields > 0 || (result.acceptedFields > 0 && result.protectedFields < result.acceptedFields)) {
            result.privacyStatus = 'Attention Required';
            result.privacyExplanation = 'Unreviewed PII, incomplete configuration coverage, or recent failed runs need attention.';
        } else if (result.completedRuns > 0 && result.acceptedFields > 0 && result.protectedFields == result.acceptedFields) {
            result.privacyStatus = 'Configuration Ready';
            result.privacyExplanation = 'All accepted PII fields have active configuration and a completed run exists. Verify execution logs to confirm actual masking.';
        }
        try {
            List<AsyncApexJob> scans = [
                SELECT CompletedDate FROM AsyncApexJob
                WHERE ApexClass.Name = 'PIIFieldScannerBatch' AND Status = 'Completed'
                WITH USER_MODE ORDER BY CompletedDate DESC LIMIT 1
            ];
            if (!scans.isEmpty() && scans[0].CompletedDate != null) {
                result.lastScanDate = scans[0].CompletedDate.format();
            }
        } catch (QueryException ex) {
            String warning = 'Last scan date is unavailable with your current permissions.';
            result.dataWarning = String.isBlank(result.dataWarning) ? warning : result.dataWarning + ' ' + warning;
        }
        return result;
    }

    // Compare Salesforce API identifiers consistently; do not strip namespace prefixes.
    private static String coverageKey(String objectApi, String fieldApi) {
        if (String.isBlank(objectApi) || String.isBlank(fieldApi) ||
            objectApi == 'null' || fieldApi == 'null') return null;
        return objectApi.trim().toLowerCase() + '.' + fieldApi.trim().toLowerCase();
    }

    public class Overview {
        @AuraEnabled public String environmentName {get;set;}
        @AuraEnabled public String dataWarning {get;set;}
        @AuraEnabled public String lastScanDate {get;set;}
        @AuraEnabled public Integer acceptedFields {get;set;}
        @AuraEnabled public Integer protectedFields {get;set;}
        @AuraEnabled public Integer reviewFields {get;set;}
        @AuraEnabled public Integer objectsConfigured {get;set;}
        @AuraEnabled public Integer fieldsConfigured {get;set;}
        @AuraEnabled public Integer completedRuns {get;set;}
        @AuraEnabled public Integer failedRuns {get;set;}
        @AuraEnabled public Integer coverage {get;set;}
        @AuraEnabled public String privacyStatus {get;set;}
        @AuraEnabled public String privacyExplanation {get;set;}
        @AuraEnabled public List<RunRow> recentRuns {get;set;}
    }
    public class RunRow {
        @AuraEnabled public Id id {get;set;}
        @AuraEnabled public String name {get;set;}
        @AuraEnabled public String status {get;set;}
        @AuraEnabled public String started {get;set;}
    }
}
