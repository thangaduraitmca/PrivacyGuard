/**
 * @class         FileAttachmentPurgeController
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
 * Apex controller behind the attachmentFilePurge LWC.
 * SECURITY: any exception (including the Sandbox-only safety block) is caught and
 * re-thrown as AuraHandledException with a clean, intentional message - LWC callers
 * never see a raw stack trace. Note the explicit setMessage() call: AuraHandledException's
 * constructor message alone isn't reliably surfaced to the client (a well-known
 * Salesforce quirk) - without setMessage(), the LWC would just see "Script-thrown
 * exception" instead of the real message.
 */
public with sharing class FileAttachmentPurgeController {
    @AuraEnabled
    public static void purgeObjects(List<String> objectApiNames, Boolean deleteAttachments, Boolean deleteFiles) {
        try {
            PrivacyGuardSecurityService.requirePurgePermission();
            if (objectApiNames == null || objectApiNames.isEmpty() || objectApiNames.size() > 10) {
                throw wrapForClient('Select between 1 and 10 supported objects.');
            }
            for (String apiName : objectApiNames) requireEligibleObject(apiName);
            FileAttachmentPurgeService.purgeForObjects(objectApiNames, deleteAttachments, deleteFiles);
        } catch (EnvironmentSafetyService.ProductionExecutionBlockedException e) {
            throw wrapForClient(e.getMessage());
        } catch (Exception e) {
            throw wrapForClient('Could not start purge: ' + e.getMessage());
        }
    }

    public class ObjectOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public ObjectOption(String label, String value) { this.label = label; this.value = value; }
    }
    public class ScanRow {
        @AuraEnabled public String objectName;
        @AuraEnabled public Integer attachmentCount = 0;
        @AuraEnabled public Integer fileLinkCount = 0;
        @AuraEnabled public String warning;
    }

    public class PurgeObjectNotSupportedException extends Exception {}

    // Apply cheap API-name exclusions before any describe calls.
    private static Boolean isExcludedName(String apiName) {
        if (String.isBlank(apiName)) return true;
        String n = apiName.toLowerCase();
        return n == 'note' || n == 'attachment' || n == 'contentnote' ||
            n.startsWith('content') || n == 'document' || n == 'user' ||
            n == 'group' || n == 'organization' || n == 'entitysubscription' ||
            n == 'feeditem' || n == 'task' || n == 'event' ||
            n.endsWith('history') || n.endsWith('share') || n.endsWith('feed') ||
            n.endsWith('changeevent') || n.endsWith('event') ||
            n.endsWith('__mdt') || n.endsWith('__e') || n.endsWith('__b');
    }

    private static Boolean isEligibleDescribe(Schema.DescribeSObjectResult d) {
        return d.isQueryable() && d.isAccessible() && d.isCreateable() &&
            d.isUpdateable() && !d.isDeprecatedAndHidden() && !d.isCustomSetting();
    }

    public static Boolean isEligibleObject(String apiName) {
        if (isExcludedName(apiName)) return false;
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(apiName);
        return objectType != null && isEligibleDescribe(objectType.getDescribe());
    }

    public static void requireEligibleObject(String apiName) {
        if (!isEligibleObject(apiName)) {
            throw new PurgeObjectNotSupportedException('Unsupported purge object: ' + apiName);
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<ObjectOption> availableObjects() {
        PrivacyGuardSecurityService.requirePurgePermission();
        List<ObjectOption> result = new List<ObjectOption>();
        Map<String, Schema.SObjectType> allTypes = Schema.getGlobalDescribe();
        for (String apiName : allTypes.keySet()) {
            if (isExcludedName(apiName)) continue;
            Schema.DescribeSObjectResult d = allTypes.get(apiName).getDescribe();
            if (isEligibleDescribe(d)) {
                result.add(new ObjectOption(d.getLabel(), apiName));
            }
        }
        return result;
    }

    @AuraEnabled
    public static List<ScanRow> scanObjects(List<String> objectApiNames) {
        PrivacyGuardSecurityService.requirePurgePermission();
        EnvironmentSafetyService.assertExecutionAllowed();
        if (objectApiNames == null || objectApiNames.isEmpty() || objectApiNames.size() > 10) {
            throw wrapForClient('Select between 1 and 10 objects per scan.');
        }
        List<ScanRow> rows = new List<ScanRow>();
        for (String apiName : objectApiNames) {
            try {
                requireEligibleObject(apiName);
                ScanRow row = new ScanRow();
                row.objectName = apiName;
                row.attachmentCount = Database.countQuery(
                    'SELECT count() FROM Attachment WHERE ParentId IN (SELECT Id FROM ' + apiName + ')');
                row.fileLinkCount = Database.countQuery(
                    'SELECT count() FROM ContentDocumentLink WHERE LinkedEntityId IN (SELECT Id FROM ' + apiName + ')');
                rows.add(row);
            } catch (Exception e) {
                ScanRow row = new ScanRow();
                row.objectName = apiName;
                row.warning = 'Unable to count related items for this object. Purge is blocked for this selection.';
                rows.add(row);
            }
        }
        return rows;
    }

    private static AuraHandledException wrapForClient(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}
