/**
 * @class         PIIScanReviewController
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
 * 1.2.6       2026-09-17   PG-PII-005       PrivacyGuard Engineering   Added namespace-safe scan-result DTO and object-centric review UX.
 * 1.3.0       2026-09-17   PG-PII-007         PrivacyGuard Engineering   Scoped review to latest completed scan and de-duplicated Object+Field candidates.
 * 1.2.8       2026-09-17   PG-PII-007       PrivacyGuard Engineering   Fixed Aura/LWC DTO serialization by exposing AuraEnabled properties with accessors.
 * 1.2.0       2026-09-16   PG-PII-002         PrivacyGuard Engineering   Added manual candidate entry and removed scoring/recommendation fields from review.
 * 1.2.5       2026-09-16   PG-PII-004         PrivacyGuard Engineering   Added governed AsyncApexJob scan status, progress reporting, candidate counts, and duplicate-run protection.
 * 1.4.1       2026-09-17   PG-CONFIG-002      PrivacyGuard Engineering   Accepted PII candidates now automatically enter inactive masking configuration.
 * 1.4.2       2026-09-17   PG-CONFIG-003      PrivacyGuard Engineering   PII acceptance no longer fails when an individual candidate is not safely maskable.
 * 1.4.3       2026-09-17   PG-CONFIG-004      PrivacyGuard Engineering   Added explicit whole-object confirmation and selection-safe review UX.
 */
/**
 * Apex controller behind the piiScanReview LWC. Lets an admin review scan findings,
 * accept/reject them in bulk, kick off a new org-wide scan, and pull ready-to-deploy
 * Custom Metadata XML for accepted rows - all without writing SOQL or Apex by hand.
 *
 * SECURITY: reads enforce object/field-level security via WITH SECURITY_ENFORCED;
 * writes strip any field the running user can't actually edit via
 * Security.stripInaccessible() rather than blindly trusting client input. All
 * exceptions are caught and re-thrown as AuraHandledException with an explicit
 * setMessage() call, since the constructor message alone isn't reliably surfaced to
 * the client (a well-known Salesforce quirk) - without it, the LWC sees only
 * "Script-thrown exception" instead of anything useful.
 */
public with sharing class PIIScanReviewController {

    private static final Set<String> VALID_STATUSES = new Set<String>{ 'New', 'Accepted', 'Removed' };

    @AuraEnabled(cacheable=true)
    public static List<ScanResultRow> getScanResults(String statusFilter) {
        try {
            PrivacyGuardSecurityService.requirePiiPermission();
            String effectiveStatus = String.isBlank(statusFilter) ? 'All' : statusFilter;
            if (effectiveStatus != 'All' && !VALID_STATUSES.contains(effectiveStatus)) {
                throw new IllegalArgumentException('Invalid status filter: ' + effectiveStatus);
            }

            // Current-review workspace is intentionally scoped to the latest PII scan.
            // Historical scan rows remain in PII_Scan_Result__c for audit purposes but are
            // never mixed into the current review set. Manual candidates are also retained.
            List<AsyncApexJob> latestJobs = [
                SELECT Id, CreatedDate
                FROM AsyncApexJob
                WHERE ApexClass.Name = 'PIIFieldScannerBatch'
                AND Status = 'Completed'
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            String latestScanId = latestJobs.isEmpty() ? null : String.valueOf(latestJobs[0].Id);

            List<PII_Scan_Result__c> records;
            if (latestScanId == null) {
                records = [
                    SELECT Id, Object_API_Name__c, Field_API_Name__c, Field_Label__c,
                           Salesforce_Field_Type__c, Detection_Reason__c, Already_Configured__c,
                           Native_Compliance_Tag__c, Review_Status__c, Scan_Batch_Id__c
                    FROM PII_Scan_Result__c
                    WHERE Scan_Batch_Id__c LIKE 'MANUAL-%'
                    WITH SECURITY_ENFORCED
                    ORDER BY Object_API_Name__c, Field_API_Name__c, CreatedDate DESC
                    LIMIT 2000
                ];
            } else {
                records = [
                    SELECT Id, Object_API_Name__c, Field_API_Name__c, Field_Label__c,
                           Salesforce_Field_Type__c, Detection_Reason__c, Already_Configured__c,
                           Native_Compliance_Tag__c, Review_Status__c, Scan_Batch_Id__c
                    FROM PII_Scan_Result__c
                    WHERE Scan_Batch_Id__c = :latestScanId OR Scan_Batch_Id__c LIKE 'MANUAL-%'
                    WITH SECURITY_ENFORCED
                    ORDER BY Object_API_Name__c, Field_API_Name__c, CreatedDate DESC
                    LIMIT 2000
                ];
            }

            // Defensive de-duplication by Object + Field. This also cleans up the display
            // if historical package versions produced duplicate rows inside a scan.
            Map<String, PII_Scan_Result__c> uniqueByField = new Map<String, PII_Scan_Result__c>();
            for (PII_Scan_Result__c rec : records) {
                if (effectiveStatus != 'All' && rec.Review_Status__c != effectiveStatus) continue;
                String key = (rec.Object_API_Name__c + '.' + rec.Field_API_Name__c).toLowerCase();
                if (!uniqueByField.containsKey(key)) uniqueByField.put(key, rec);
            }

            List<ScanResultRow> rows = new List<ScanResultRow>();
            for (PII_Scan_Result__c rec : uniqueByField.values()) rows.add(new ScanResultRow(rec));
            return rows;
        } catch (Exception e) {
            throw wrapForClient('Could not load scan results: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void updateReviewStatus(List<Id> recordIds, String newStatus) {
        try {
            PrivacyGuardSecurityService.requirePiiPermission();
            if (recordIds == null || recordIds.isEmpty()) {
                throw new IllegalArgumentException('No records selected.');
            }
            if (!VALID_STATUSES.contains(newStatus)) {
                throw new IllegalArgumentException('Invalid status: ' + newStatus);
            }

            List<PII_Scan_Result__c> toUpdate = new List<PII_Scan_Result__c>();
            for (Id recId : recordIds) {
                toUpdate.add(new PII_Scan_Result__c(Id = recId, Review_Status__c = newStatus));
            }

            // Strip any field the running user can't actually edit rather than trusting
            // the client - update() then only touches fields this user is permitted to.
            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.UPDATABLE, toUpdate);
            update decision.getRecords();

            // Acceptance is the governance approval to enter masking scope. Create the
            // configuration immediately, but keep it inactive until an administrator
            // explicitly chooses a masking strategy and activates it.
            if (newStatus == 'Accepted') {
                List<PII_Scan_Result__c> accepted = [
                    SELECT Object_API_Name__c, Field_API_Name__c
                    FROM PII_Scan_Result__c WHERE Id IN :recordIds
                ];
                List<PrivacyGuardConfigurationController.FieldRow> configRows = new List<PrivacyGuardConfigurationController.FieldRow>();
                for (PII_Scan_Result__c finding : accepted) {
                    PrivacyGuardConfigurationController.FieldRow row = new PrivacyGuardConfigurationController.FieldRow();
                    row.objectApiName = finding.Object_API_Name__c;
                    row.fieldApiName = finding.Field_API_Name__c;
                    row.active = false;
                    row.source = 'PII Discovery';
                    configRows.add(row);
                }
                PrivacyGuardConfigurationController.saveAcceptedConfigurations(configRows);
            }
        } catch (Exception e) {
            throw wrapForClient('Could not update review status: ' + e.getMessage());
        }
    }


    /** Adds an administrator-selected field to the review queue without claiming it was auto-detected. */
    @AuraEnabled
    public static Id addManualCandidate(String objectApiName, String fieldApiName) {
        try {
            PrivacyGuardSecurityService.requirePiiPermission();
            if (String.isBlank(objectApiName) || String.isBlank(fieldApiName)) {
                throw new IllegalArgumentException('Object API name and Field API name are required.');
            }
            Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName.trim());
            if (objectType == null) throw new IllegalArgumentException('Unknown Salesforce object: ' + objectApiName);
            Schema.SObjectField fieldToken = objectType.getDescribe().fields.getMap().get(fieldApiName.trim());
            if (fieldToken == null) throw new IllegalArgumentException('Unknown field ' + fieldApiName + ' on ' + objectApiName + '.');
            Schema.DescribeFieldResult d = fieldToken.getDescribe();
            String objectName = objectType.getDescribe().getName();
            String fieldName = d.getName();
            List<PII_Scan_Result__c> existing = [
                SELECT Id FROM PII_Scan_Result__c
                WHERE Object_API_Name__c = :objectName AND Field_API_Name__c = :fieldName
                AND Review_Status__c != 'Removed' LIMIT 1
            ];
            if (!existing.isEmpty()) return existing[0].Id;
            PII_Scan_Result__c candidate = new PII_Scan_Result__c(
                Object_API_Name__c = objectName, Field_API_Name__c = fieldName,
                Field_Label__c = d.getLabel(), Salesforce_Field_Type__c = String.valueOf(d.getType()),
                Detection_Reason__c = 'Manually added by administrator',
                Already_Configured__c = false, Review_Status__c = 'New',
                Scan_Batch_Id__c = 'MANUAL-' + String.valueOf(DateTime.now().getTime())
            );
            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, new List<PII_Scan_Result__c>{candidate});
            List<SObject> creatable = decision.getRecords();
            if (creatable.isEmpty()) throw new SecurityException('No create access to PII scan results.');
            insert creatable;
            return ((PII_Scan_Result__c)creatable[0]).Id;
        } catch (Exception e) {
            throw wrapForClient('Could not add masking-scope candidate: ' + e.getMessage());
        }
    }

    /** Starts one governed org-wide PII scan. A second active scan is deliberately blocked. */
    @AuraEnabled
    public static Id runScan() {
        try {
            PrivacyGuardSecurityService.requirePiiPermission();
            List<AsyncApexJob> active = [
                SELECT Id FROM AsyncApexJob
                WHERE ApexClass.Name = 'PIIFieldScannerBatch'
                AND Status IN ('Holding','Preparing','Queued','Processing')
                ORDER BY CreatedDate DESC LIMIT 1
            ];
            if (!active.isEmpty()) {
                throw new IllegalArgumentException('A PrivacyGuard PII discovery scan is already running. Job: ' + active[0].Id);
            }
            return Database.executeBatch(new PIIFieldScannerBatch(PIIFieldScannerBatch.getAllScannableObjects()), 1);
        } catch (Exception e) {
            throw wrapForClient('Could not start scan: ' + e.getMessage());
        }
    }

    /**
     * Returns live, read-only scan telemetry from AsyncApexJob. If jobId is null,
     * the most recent PrivacyGuard PII scanner job is returned so status survives a page refresh.
     */
    @AuraEnabled
    public static ScanStatus getScanStatus(Id jobId) {
        try {
            PrivacyGuardSecurityService.requirePiiPermission();
            List<AsyncApexJob> jobs;
            if (jobId == null) {
                jobs = [SELECT Id, Status, JobItemsProcessed, TotalJobItems, NumberOfErrors,
                               CreatedDate, CompletedDate, ExtendedStatus
                        FROM AsyncApexJob
                        WHERE ApexClass.Name = 'PIIFieldScannerBatch'
                        ORDER BY CreatedDate DESC LIMIT 1];
            } else {
                jobs = [SELECT Id, Status, JobItemsProcessed, TotalJobItems, NumberOfErrors,
                               CreatedDate, CompletedDate, ExtendedStatus
                        FROM AsyncApexJob WHERE Id = :jobId AND ApexClass.Name = 'PIIFieldScannerBatch' LIMIT 1];
            }
            if (jobs.isEmpty()) return null;

            AsyncApexJob job = jobs[0];
            String scanBatchId = String.valueOf(job.Id);
            Integer candidateCount = [SELECT COUNT() FROM PII_Scan_Result__c WHERE Scan_Batch_Id__c = :scanBatchId];
            ScanStatus result = new ScanStatus();
            result.jobId = job.Id;
            result.status = job.Status;
            result.processed = job.JobItemsProcessed == null ? 0 : job.JobItemsProcessed;
            result.total = job.TotalJobItems == null ? 0 : job.TotalJobItems;
            result.errors = job.NumberOfErrors == null ? 0 : job.NumberOfErrors;
            result.candidatesFound = candidateCount;
            result.startedAt = job.CreatedDate;
            result.completedAt = job.CompletedDate;
            result.detail = job.ExtendedStatus;
            String warningKey='PII_Classification_'+scanBatchId;
            List<Masking_Log__c> warnings=[SELECT Id FROM Masking_Log__c WHERE Job_Name__c=:warningKey LIMIT 1];
            result.classificationWarning=warnings.isEmpty()?null:'Classification lookup was incomplete for one or more objects. Keyword and field-type checks continued. Review Masking Logs for details.';
            return result;
        } catch (Exception e) {
            throw wrapForClient('Could not load scan status: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static List<GeneratedFile> getGeneratedMetadataFiles() {
        try {
            PrivacyGuardSecurityService.requirePiiPermission();
            Map<String, String> filesByName = MaskingConfigPromoter.generateMetadataXmlForAcceptedFindings();
            List<GeneratedFile> results = new List<GeneratedFile>();
            for (String fileName : filesByName.keySet()) {
                GeneratedFile gf = new GeneratedFile();
                gf.fileName = fileName;
                gf.content = filesByName.get(fileName);
                results.add(gf);
            }
            return results;
        } catch (Exception e) {
            throw wrapForClient('Could not generate configuration files: ' + e.getMessage());
        }
    }

    private static AuraHandledException wrapForClient(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }



    /** Namespace-safe DTO for LWC. Never expose namespaced SObject JSON keys to the UI contract. */
    public class ScanResultRow {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String objectApiName { get; set; }
        @AuraEnabled public String fieldApiName { get; set; }
        @AuraEnabled public String fieldLabel { get; set; }
        @AuraEnabled public String salesforceFieldType { get; set; }
        @AuraEnabled public String detectionReason { get; set; }
        @AuraEnabled public String nativeComplianceTag { get; set; }
        @AuraEnabled public Boolean alreadyConfigured { get; set; }
        @AuraEnabled public String reviewStatus { get; set; }
        public ScanResultRow(PII_Scan_Result__c rec) {
            id = rec.Id; objectApiName = rec.Object_API_Name__c; fieldApiName = rec.Field_API_Name__c;
            fieldLabel = rec.Field_Label__c; salesforceFieldType = rec.Salesforce_Field_Type__c;
            detectionReason = rec.Detection_Reason__c; alreadyConfigured = rec.Already_Configured__c;
            reviewStatus = rec.Review_Status__c; nativeComplianceTag=rec.Native_Compliance_Tag__c;
        }
    }

    public class ScanStatus {
        @AuraEnabled public String classificationWarning {get;set;}
        @AuraEnabled public Id jobId { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Integer processed { get; set; }
        @AuraEnabled public Integer total { get; set; }
        @AuraEnabled public Integer errors { get; set; }
        @AuraEnabled public Integer candidatesFound { get; set; }
        @AuraEnabled public Datetime startedAt { get; set; }
        @AuraEnabled public Datetime completedAt { get; set; }
        @AuraEnabled public String detail { get; set; }
    }

    public class GeneratedFile {
        @AuraEnabled public String fileName { get; set; }
        @AuraEnabled public String content { get; set; }
    }
}
