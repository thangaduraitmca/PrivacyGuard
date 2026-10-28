/**
 * @class         PIIFieldScannerService
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
 * 1.2.0       2026-09-16   PG-PII-001         PrivacyGuard Engineering   Removed confidence/scoring and masking recommendations; discovery now returns candidates and evidence only.
 * 1.2.4       2026-09-16   PG-PII-003         PrivacyGuard Engineering   Removed Tooling API callouts from discovery; scanner now uses deterministic Describe + keyword signals only.
 * 1.3.0       2026-09-17   PG-PII-007         PrivacyGuard Engineering   Added token-aware keyword matching to prevent substring false positives.
 * 1.4.4       2026-09-17   PG-PII-009         PrivacyGuard Engineering   Exclude every field already present in masking configuration, active or inactive, from future PII discovery.
 */
/**
 * Scans one object's field describe results for potential PII candidates using deterministic signals:
 *   1. Field type — Email/Phone are PII by definition; EncryptedString means someone
 *      already decided it was sensitive.
 *   2. Keyword match — field label/API name checked against PII_Keyword__mdt (tune the
 *      dictionary without touching code).
 *   3. Native classification — compliance categories and sensitive classification levels.
 *   4. Already configured — fields present in Masking_Configuration__mdt or
 *      Masking_Field_Config__c are excluded from discovery, regardless of Active status.
 *
 * Writes candidates and the reason they were identified to PII_Scan_Result__c for admin review.
 * PrivacyGuard deliberately assigns no score, confidence, or recommended masking strategy.
 * Discovery never changes masking scope automatically.
 */
public with sharing class PIIFieldScannerService {

    private static List<PII_Keyword__mdt> cachedKeywords;
    private static Set<String> cachedConfiguredKeys;

    /** Scans an object using Salesforce Describe, keywords and native classification metadata. */
    public static List<PII_Scan_Result__c> scanObject(String objectApiName, String scanBatchId) {
        return scanWithClassifications(objectApiName,scanBatchId,true);
    }
    private static List<PII_Scan_Result__c> scanWithClassifications(String objectApiName,String scanBatchId,Boolean includeNative) {
        List<PII_Scan_Result__c> findings = new List<PII_Scan_Result__c>();

        Schema.SObjectType sobjType = Schema.getGlobalDescribe().get(objectApiName);
        if (sobjType == null) {
            return findings;
        }

        Schema.DescribeSObjectResult objDescribe = sobjType.getDescribe();
        Set<String> alreadyConfigured = getConfiguredFieldKeys();
        Map<String,ComplianceCategorizationService.ComplianceInfo> nativeTags = includeNative
            ? ComplianceCategorizationService.getComplianceTags(objectApiName)
            : new Map<String,ComplianceCategorizationService.ComplianceInfo>();
        if(includeNative && String.isNotBlank(ComplianceCategorizationService.getLastWarning())) {
            MaskingLogger.logInfo('PII_Classification_'+scanBatchId,objectApiName+': '+ComplianceCategorizationService.getLastWarning());
        }

        for (Schema.SObjectField field : objDescribe.fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
            String fieldApiName = fieldDescribe.getName();
            String fieldLabel = fieldDescribe.getLabel();
            Schema.DisplayType fieldType = fieldDescribe.getType();
            String configKey = (objectApiName + '.' + fieldApiName).toLowerCase();
            // Configuration is the authoritative masking scope. Once a field has been
            // configured (even inactive / awaiting a strategy), discovery must not
            // re-suggest it. Deleting the configuration makes it discoverable again.
            if (alreadyConfigured.contains(configKey)) {
                continue;
            }

            String reason = null;

            if (fieldType == Schema.DisplayType.EMAIL) {
                reason = 'Field type: Email';
            } else if (fieldType == Schema.DisplayType.PHONE) {
                reason = 'Field type: Phone';
            } else if (fieldType == Schema.DisplayType.ENCRYPTEDSTRING) {
                reason = 'Field is already encrypted';
            }

            if (reason == null) {
                String haystack = normalizeForKeywordMatch(fieldLabel + ' ' + fieldApiName);
                for (String keyword : getKeywordStrings()) {
                    if (String.isBlank(keyword)) continue;
                    String needle = normalizeForKeywordMatch(keyword);
                    // Match complete normalized tokens/phrases only. This prevents short
                    // keywords such as TIN from matching unrelated names like OperatingHoursId.
                    if ((' ' + haystack + ' ').contains(' ' + needle + ' ')) {
                        reason = 'Keyword match: ' + keyword;
                        break;
                    }
                }
            }

            ComplianceCategorizationService.ComplianceInfo classification=nativeTags.get(fieldApiName.toLowerCase());
            // Test providers and existing callers may use canonical-case field API names.
            if(classification==null)classification=nativeTags.get(fieldApiName);
            String classificationTags=ComplianceCategorizationService.describeTags(classification);
            if(ComplianceCategorizationService.isSensitive(classification)) {
                String classificationReason='Salesforce Data Classification: '+classificationTags;
                reason=reason==null?classificationReason:reason+'; '+classificationReason;
            }
            if (reason != null) {
                if(reason.length()>255)reason=reason.substring(0,252)+'...';
                findings.add(new PII_Scan_Result__c(
                    Object_API_Name__c = objectApiName,
                    Field_API_Name__c = fieldApiName,
                    Field_Label__c = fieldLabel,
                    Salesforce_Field_Type__c = String.valueOf(fieldType),
                    Detection_Reason__c = reason,
                    Already_Configured__c = false,
                    Native_Compliance_Tag__c = classificationTags,
                    Review_Status__c = 'New',
                    Scan_Batch_Id__c = scanBatchId
                ));
            }
        }
        return findings;
    }

    /**
     * Compatibility overload retained for callers compiled against v1.2.x.
     * includeNativeComplianceTags controls native SOQL classification discovery; no HTTP callouts are used.
     */
    public static List<PII_Scan_Result__c> scanObject(String objectApiName, String scanBatchId, Boolean includeNativeComplianceTags) {
        return scanWithClassifications(objectApiName,scanBatchId,includeNativeComplianceTags==true);
    }

    @TestVisible
    private static String normalizeForKeywordMatch(String value) {
        if (String.isBlank(value)) return '';
        String normalized = value.replaceAll('([a-z0-9])([A-Z])', '$1 $2');
        normalized = normalized.replaceAll('[_\\-]+', ' ');
        normalized = normalized.replaceAll('[^A-Za-z0-9 ]+', ' ');
        normalized = normalized.toLowerCase().replaceAll('\\s+', ' ').trim();
        return normalized;
    }

    private static List<String> getKeywordStrings() {
        List<String> values = new List<String>();
        Map<String, Boolean> orgState = new Map<String, Boolean>();
        Map<String, String> orgValue = new Map<String, String>();
        for (PII_Keyword_Config__c k : [SELECT Keyword__c, Is_Active__c FROM PII_Keyword_Config__c]) {
            if (String.isBlank(k.Keyword__c)) continue;
            String key = normalizeForKeywordMatch(k.Keyword__c);
            orgState.put(key, k.Is_Active__c);
            orgValue.put(key, k.Keyword__c);
        }
        if (cachedKeywords == null) cachedKeywords = [SELECT Keyword__c FROM PII_Keyword__mdt];
        Set<String> emitted = new Set<String>();
        for (PII_Keyword__mdt k : cachedKeywords) {
            if (String.isBlank(k.Keyword__c)) continue;
            String key = normalizeForKeywordMatch(k.Keyword__c);
            if (orgState.containsKey(key) && orgState.get(key) == false) continue;
            if (!emitted.contains(key)) { values.add(k.Keyword__c); emitted.add(key); }
        }
        for (String key : orgState.keySet()) {
            if (orgState.get(key) == true && !emitted.contains(key)) { values.add(orgValue.get(key)); emitted.add(key); }
        }
        return values;
    }

    private static Set<String> getConfiguredFieldKeys() {
        if (cachedConfiguredKeys == null) {
            cachedConfiguredKeys = new Set<String>();
            for (Masking_Configuration__mdt cfg : [
                SELECT Object_API_Name__c, Field_API_Name__c
                FROM Masking_Configuration__mdt
            ]) {
                cachedConfiguredKeys.add((cfg.Object_API_Name__c + '.' + cfg.Field_API_Name__c).toLowerCase());
            }
            for (Masking_Field_Config__c cfg : [SELECT Object_API_Name__c, Field_API_Name__c FROM Masking_Field_Config__c]) {
                cachedConfiguredKeys.add((cfg.Object_API_Name__c + '.' + cfg.Field_API_Name__c).toLowerCase());
            }
        }
        return cachedConfiguredKeys;
    }
}
