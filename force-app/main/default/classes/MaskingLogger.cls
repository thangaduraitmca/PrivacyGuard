/**
 * @class         MaskingLogger
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
 * Writes structured entries to Masking_Log__c so failures are meaningful and
 * queryable instead of buried in debug logs. queueLog()/flush() batch inserts
 * within a single batch execute() chunk; logInfo()/logError() insert immediately
 * for one-off/job-level events.
 */
public with sharing class MaskingLogger {

    public class MaskingLogPersistenceException extends Exception {}

    private static List<Masking_Log__c> pendingLogs = new List<Masking_Log__c>();

    public static void logInfo(String jobName, String message) {
        insertLogNow(jobName, null, null, null, message, 'Success');
    }

    public static void logError(String jobName, String objectApiName, Id recordId, String fieldApiName, String errorMessage) {
        insertLogNow(jobName, objectApiName, recordId, fieldApiName, errorMessage, 'Failed');
    }

    public static void queueLog(String jobName, String objectApiName, Id recordId, String fieldApiName, String message, String status) {
        pendingLogs.add(new Masking_Log__c(
            Job_Name__c = jobName,
            Object_API_Name__c = objectApiName,
            Record_Id__c = recordId != null ? String.valueOf(recordId) : null,
            Field_API_Name__c = fieldApiName,
            Error_Message__c = message,
            Status__c = status
        ));
    }

    public static void flush() {
        if (!pendingLogs.isEmpty()) {
            List<Masking_Log__c> toInsert = pendingLogs;
            pendingLogs = new List<Masking_Log__c>();
            try {
                insert toInsert;
            } catch (Exception e) {
                // Fail closed: the surrounding execute transaction must roll back its
                // masking DML if the failure audit cannot be persisted.
                throw new MaskingLogPersistenceException('PrivacyGuard failure logs could not be saved: ' + e.getMessage());
            }
        }
    }

    private static void insertLogNow(String jobName, String objectApiName, Id recordId, String fieldApiName, String message, String status) {
        try {
            insert new Masking_Log__c(
                Job_Name__c = jobName,
                Object_API_Name__c = objectApiName,
                Record_Id__c = recordId != null ? String.valueOf(recordId) : null,
                Field_API_Name__c = fieldApiName,
                Error_Message__c = message,
                Status__c = status
            );
        } catch (Exception e) {
            // A missing audit entry must never be reported as successful logging.
            throw new MaskingLogPersistenceException(
                'PrivacyGuard could not persist a masking audit entry: ' + e.getMessage());
        }
    }

    public static void queueDetailedLog(Id runId, String jobName, String objectApiName, Id recordId, String fieldApiName, String message, String status) {
        String category = categorize(message);
        pendingLogs.add(new Masking_Log__c(Job_Name__c=jobName,Object_API_Name__c=objectApiName,Record_Id__c=recordId!=null?String.valueOf(recordId):null,Field_API_Name__c=fieldApiName,Error_Message__c=message,Status__c=status,Run_Id__c=runId!=null?String.valueOf(runId):null,Error_Category__c=category,Admin_Message__c=adminMessage(category,message),Suggested_Action__c=suggestedAction(category),Technical_Details__c=message));
    }
    private static String categorize(String m){String x=m==null?'':m.toUpperCase();if(x.contains('FIELD_CUSTOM_VALIDATION_EXCEPTION'))return 'Validation Rule';if(x.contains('REQUIRED_FIELD_MISSING'))return 'Required Field';if(x.contains('UNABLE_TO_LOCK_ROW'))return 'Record Locked';if(x.contains('DUPLICATE'))return 'Duplicate Rule';if(x.contains('FLOW')||x.contains('PROCESS'))return 'Automation/Flow';if(x.contains('LIMIT'))return 'Governor Limit';if(x.contains('INSUFFICIENT_ACCESS'))return 'Permission';return 'Salesforce Error';}
    private static String adminMessage(String c,String m){return 'PrivacyGuard could not mask this record. Category: '+c+'. Review the affected object/field and the technical details before rerunning.';}
    private static String suggestedAction(String c){if(c=='Validation Rule')return 'Review the validation rule and masking pattern, correct the conflict, then use Rerun.';if(c=='Record Locked')return 'Wait for the record lock to clear, then use Rerun.';if(c=='Automation/Flow')return 'Review the failing Flow/automation and its dependency on the masked value, then use Rerun.';if(c=='Permission')return 'Review PrivacyGuard package permissions and object/field access, then use Rerun.';return 'Correct the underlying Salesforce error, then use Rerun. Only failed records from the selected parent run will be processed.';}
}
