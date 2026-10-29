/** PrivacyGuard dashboard. Configuration and execution indicators are not compliance certification. */
public with sharing class PrivacyGuardHomeController {
    @AuraEnabled(cacheable=true)
    public static Overview getOverview() {
        PrivacyGuardSecurityService.requirePiiPermission();
        Overview result = new Overview();
        result.environmentName = [SELECT Name FROM Organization LIMIT 1].Name;
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
            String scanObject = PII_Scan_Result__c.SObjectType.getDescribe().getName();
            String scanObjField = fieldName(PII_Scan_Result__c.SObjectType, 'Object_API_Name__c');
            String scanFieldField = fieldName(PII_Scan_Result__c.SObjectType, 'Field_API_Name__c');
            String scanStatusField = fieldName(PII_Scan_Result__c.SObjectType, 'Review_Status__c');
            for (SObject row : Database.query('SELECT ' + scanObjField + ', ' + scanFieldField + ', ' + scanStatusField +
                ' FROM ' + scanObject + ' WITH USER_MODE ORDER BY CreatedDate DESC, Id DESC LIMIT 50000')) {
                String key = coverageKey(String.valueOf(row.get(scanObjField)), String.valueOf(row.get(scanFieldField)));
                if (key == null || reviewedKeys.contains(key)) continue;
                reviewedKeys.add(key);
                String status = String.valueOf(row.get(scanStatusField));
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

        String configObject = Masking_Field_Config__c.SObjectType.getDescribe().getName();
        String configObjField = fieldName(Masking_Field_Config__c.SObjectType, 'Object_API_Name__c');
        String configFieldField = fieldName(Masking_Field_Config__c.SObjectType, 'Field_API_Name__c');
        String configActiveField = fieldName(Masking_Field_Config__c.SObjectType, 'Is_Active__c');
        Set<String> configuredKeys = new Set<String>();
        Set<String> configuredObjects = new Set<String>();
        for (SObject row : Database.query('SELECT ' + configObjField + ', ' + configFieldField + ' FROM ' + configObject + ' WHERE ' + configActiveField + ' = true WITH USER_MODE LIMIT 50000')) {
            String objectApi = String.valueOf(row.get(configObjField));
            String key = coverageKey(objectApi, String.valueOf(row.get(configFieldField)));
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
            Schema.DescribeSObjectResult runDescribe = Masking_Job_Run__c.SObjectType.getDescribe();
            if (!runDescribe.isAccessible()) {
                throw new AuraHandledException('Read access to Masking Job Run is required.');
            }
            String runObject = runDescribe.getName();
            String runStatusField = fieldName(Masking_Job_Run__c.SObjectType, 'Status__c');
            String runStartedField = fieldName(Masking_Job_Run__c.SObjectType, 'Started_At__c');
            Map<String, Schema.SObjectField> runFields = runDescribe.fields.getMap();
            for (String requiredField : new List<String>{runStatusField, runStartedField}) {
                Boolean accessible = false;
                for (Schema.SObjectField fieldToken : runFields.values()) {
                    Schema.DescribeFieldResult fieldDescribe = fieldToken.getDescribe();
                    if (fieldDescribe.getName().equalsIgnoreCase(requiredField)) {
                        accessible = fieldDescribe.isAccessible();
                        break;
                    }
                }
                if (!accessible) {
                    throw new AuraHandledException('Read access to Masking Job Run field ' + requiredField + ' is required.');
                }
            }
            // Aggregate all accessible runs rather than counting only the 100 most recent.
            for (AggregateResult aggregateRow : Database.query(
                'SELECT ' + runStatusField + ' runStatus, COUNT(Id) runCount FROM ' + runObject +
                ' WITH USER_MODE GROUP BY ' + runStatusField
            )) {
                String status = String.valueOf(aggregateRow.get('runStatus'));
                Integer count = (Integer)aggregateRow.get('runCount');
                if (status == 'Completed') result.completedRuns += count;
                if (status == 'Failed' || status == 'Completed with Errors') result.failedRuns += count;
            }
            // Recent-run list is independent of the aggregate totals.
            for (SObject job : Database.query(
                'SELECT Id, Name, ' + runStatusField + ', ' + runStartedField +
                ' FROM ' + runObject + ' WITH USER_MODE ORDER BY CreatedDate DESC LIMIT 5'
            )) {
                RunRow row = new RunRow();
                row.id = (Id)job.get('Id');
                row.name = String.valueOf(job.get('Name'));
                row.status = String.valueOf(job.get(runStatusField));
                Datetime started = (Datetime)job.get(runStartedField);
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
        List<AsyncApexJob> scans = [SELECT CompletedDate FROM AsyncApexJob WHERE ApexClass.Name = 'PIIFieldScannerBatch' AND Status = 'Completed' ORDER BY CompletedDate DESC LIMIT 1];
        if (!scans.isEmpty() && scans[0].CompletedDate != null) result.lastScanDate = scans[0].CompletedDate.format();
        return result;
    }

    // Compare Salesforce API identifiers consistently; do not strip namespace prefixes.
    private static String coverageKey(String objectApi, String fieldApi) {
        if (String.isBlank(objectApi) || String.isBlank(fieldApi) ||
            objectApi == 'null' || fieldApi == 'null') return null;
        return objectApi.trim().toLowerCase() + '.' + fieldApi.trim().toLowerCase();
    }

    // Resolve either local or namespace-qualified names from the actual org schema.
    // Managed-package describe maps can expose keys differently across contexts.
    private static String fieldName(Schema.SObjectType objectType, String localName) {
        Map<String, Schema.SObjectField> fields = PrivacyGuardSchema.fields(objectType.getDescribe());
        String objectApi = objectType.getDescribe().getName();
        String namespacePrefix = '';
        Integer separator = objectApi.indexOf('__');
        if (separator > 0) namespacePrefix = objectApi.substring(0, separator) + '__';

        List<String> candidates = new List<String>{ localName };
        if (namespacePrefix != '') candidates.add(namespacePrefix + localName);
        for (String candidate : candidates) {
            if (fields.containsKey(candidate)) {
                return fields.get(candidate).getDescribe().getName();
            }
        }
        // Use the field's described API name, not assumptions about map keys.
        for (Schema.SObjectField token : fields.values()) {
            String actual = token.getDescribe().getName();
            if (actual.equalsIgnoreCase(localName) ||
                (namespacePrefix != '' && actual.equalsIgnoreCase(namespacePrefix + localName)) ||
                actual.toLowerCase().endsWith('__' + localName.toLowerCase())) {
                return actual;
            }
        }
        throw new AuraHandledException('PrivacyGuard schema mismatch: missing ' + localName + ' on ' + objectApi);
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
