/** File inventory and explicitly confirmed, permission-checked sandbox deletion. */
public with sharing class PrivacyGuardFileInventoryController {
    private static final Integer PAGE_SIZE = 100;
    private static final Integer RELATION_LIMIT = 2000;
    public class InventoryRow {
        @AuraEnabled public String id;
        @AuraEnabled public String kind;
        @AuraEnabled public String title;
        @AuraEnabled public String fileType;
        @AuraEnabled public Long sizeBytes;
        @AuraEnabled public String owner;
        @AuraEnabled public Datetime uploadedAt;
        @AuraEnabled public Datetime modifiedAt;
        @AuraEnabled public String linkedRecords;
        @AuraEnabled public String libraries;
        @AuraEnabled public String relationshipStatus;
        @AuraEnabled public String completeness;
    }
    public class InventoryPage {
        @AuraEnabled public List<InventoryRow> rows = new List<InventoryRow>();
        @AuraEnabled public Id nextCursor;
        @AuraEnabled public Boolean hasMore = false;
        @AuraEnabled public Datetime startedAt;
        @AuraEnabled public List<String> warnings = new List<String>();
    }
    @AuraEnabled
    public static InventoryPage scanPage(String kind, Id afterId, Datetime startedAt) {
        if (!PrivacyGuardSecurityService.hasPermission(PrivacyGuardSecurityService.PII_PERMISSION) &&
            !PrivacyGuardSecurityService.hasPermission(PrivacyGuardSecurityService.PURGE_PERMISSION)) {
            throw client('PII administration or file purge permission is required to view the file inventory.');
        }
        if (kind != 'Files' && kind != 'Attachments') throw client('Choose Files or Attachments.');
        Schema.SObjectType expected = kind == 'Files' ? ContentDocument.SObjectType : Attachment.SObjectType;
        if (afterId != null && afterId.getSObjectType() != expected) throw client('Invalid inventory cursor. Start a new scan.');
        InventoryPage page = new InventoryPage();
        page.startedAt = startedAt == null ? System.now() : startedAt;
        if (kind == 'Files') readFiles(page, afterId);
        else readAttachments(page, afterId);
        if(afterId==null) PrivacyGuardAuditService.record('Files','Inventory started',null,'Requested '+kind+' inventory. This entry does not certify completion.');
        return page;
    }
    public class DeleteOutcome {
        @AuraEnabled public Id id;
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
    }
    @AuraEnabled
    public static List<DeleteOutcome> deleteSelected(List<Id> recordIds, String confirmation) {
        PrivacyGuardSecurityService.requirePurgePermission();
        EnvironmentSafetyService.assertExecutionAllowed();
        if (confirmation != 'DELETE' || recordIds == null || recordIds.isEmpty() || recordIds.size() > 100)
            throw client('Confirm DELETE and submit between 1 and 100 selected items per request.');
        Set<Id> ids = new Set<Id>(recordIds);
        Set<Id> docs = new Set<Id>(); Set<Id> attachments = new Set<Id>();
        for (Id item : ids) {
            if (item == null) throw client('Invalid selected item.');
            if (item.getSObjectType() == ContentDocument.SObjectType) docs.add(item);
            else if (item.getSObjectType() == Attachment.SObjectType) attachments.add(item);
            else throw client('Only Salesforce Files and legacy Attachments can be deleted here.');
        }
        List<SObject> records = new List<SObject>();
        records.addAll([SELECT Id FROM ContentDocument WHERE Id IN :docs WITH USER_MODE]);
        records.addAll([SELECT Id FROM Attachment WHERE Id IN :attachments WITH USER_MODE]);
        List<DeleteOutcome> outcomes = new List<DeleteOutcome>();
        Set<Id> found = new Set<Id>();
        Savepoint checkpoint = Database.setSavepoint();
        try {
            List<Database.DeleteResult> results = Database.delete(records, false, AccessLevel.USER_MODE);
            List<Masking_Log__c> audit = new List<Masking_Log__c>();
            for (Integer i=0; i<records.size(); i++) {
                DeleteOutcome outcome = new DeleteOutcome(); outcome.id = records[i].Id;
                found.add(outcome.id); outcome.success = results[i].isSuccess();
                outcome.message = outcome.success ? 'Deleted' : String.valueOf(results[i].getErrors()[0].getStatusCode()) + ': ' + results[i].getErrors()[0].getMessage();
                outcomes.add(outcome);
                audit.add(new Masking_Log__c(Job_Name__c='Selected_File_Deletion',Activity_Category__c='Files',Activity_Action__c='Delete', Object_API_Name__c=String.valueOf(records[i].getSObjectType()), Record_Id__c=String.valueOf(outcome.id), Status__c=outcome.success?'Success':'Failed', Error_Message__c=outcome.message.left(255)));
            }
            for (Id item : ids) if (!found.contains(item)) {
                DeleteOutcome outcome = new DeleteOutcome(); outcome.id=item; outcome.success=false;
                outcome.message='Item is no longer available or is not accessible.'; outcomes.add(outcome);
                audit.add(new Masking_Log__c(Job_Name__c='Selected_File_Deletion',Activity_Category__c='Files',Activity_Action__c='Delete',Record_Id__c=String.valueOf(item),Status__c='Failed',Error_Message__c=outcome.message));
            }
            // Audit is mandatory: a logging failure rolls back this request's deletions.
            insert audit;
        } catch (Exception ex) {
            Database.rollback(checkpoint);
            throw client('This deletion request was rolled back. Verify delete permissions and audit-log availability.');
        }
        return outcomes;
    }
    private static void readFiles(InventoryPage page, Id afterId) {
        Datetime cutoff=page.startedAt;
        List<ContentDocument> documents;
        try {
            if(afterId == null) documents=[SELECT Id, Title, FileType, ContentSize, Owner.Name, CreatedDate, LastModifiedDate
                FROM ContentDocument WHERE CreatedDate <= :cutoff WITH USER_MODE ORDER BY Id LIMIT 101];
            else documents=[SELECT Id, Title, FileType, ContentSize, Owner.Name, CreatedDate, LastModifiedDate
                FROM ContentDocument WHERE Id > :afterId AND CreatedDate <= :cutoff
                WITH USER_MODE ORDER BY Id LIMIT 101];
        } catch (Exception ex) {
            throw client('Salesforce Files metadata is unavailable. Check file visibility and read access.');
        }
        page.hasMore=documents.size()>PAGE_SIZE;
        if (page.hasMore) documents.remove(PAGE_SIZE);
        if (documents.isEmpty()) return;
        Set<Id> documentIds=new Set<Id>();
        Map<Id,List<String>> links=new Map<Id,List<String>>();
        Map<Id,List<String>> libraries=new Map<Id,List<String>>();
        Set<Id> businessLinked=new Set<Id>();
        for(ContentDocument item:documents) {
            documentIds.add(item.Id);links.put(item.Id,new List<String>());libraries.put(item.Id,new List<String>());
        }
        Boolean relationshipsComplete=true;
        try {
            List<ContentDocumentLink> rows=[SELECT ContentDocumentId,LinkedEntityId FROM ContentDocumentLink
                WHERE ContentDocumentId IN :documentIds WITH USER_MODE ORDER BY Id LIMIT 2001];
            if(rows.size()>RELATION_LIMIT) {
                relationshipsComplete=false;rows.remove(RELATION_LIMIT);
                page.warnings.add('A page exceeded 2,000 visible file links. File rows are included, but relationship details are partial.');
            }
            for(ContentDocumentLink link:rows) {
                String objectName=link.LinkedEntityId.getSObjectType().getDescribe().getName();
                links.get(link.ContentDocumentId).add(objectName+':'+String.valueOf(link.LinkedEntityId));
                if(!new Set<String>{'User','Group','Organization','ContentWorkspace'}.contains(objectName)) businessLinked.add(link.ContentDocumentId);
            }
        } catch(Exception ex) {
            relationshipsComplete=false;
            page.warnings.add('File link details are unavailable for this page. Relationship status is unknown.');
        }
        Boolean librariesComplete=true;
        try {
            List<ContentWorkspaceDoc> memberships=[SELECT ContentDocumentId,ContentWorkspace.Name FROM ContentWorkspaceDoc
                WHERE ContentDocumentId IN :documentIds WITH USER_MODE ORDER BY Id LIMIT 2001];
            if(memberships.size()>RELATION_LIMIT) {
                librariesComplete=false;memberships.remove(RELATION_LIMIT);
                page.warnings.add('Library membership details exceeded the page limit and are partial.');
            }
            for(ContentWorkspaceDoc membership:memberships) libraries.get(membership.ContentDocumentId).add(membership.ContentWorkspace.Name);
        } catch(Exception ex) {
            librariesComplete=false;page.warnings.add('Library membership details are unavailable for this page.');
        }
        for(ContentDocument item:documents) {
            InventoryRow row=new InventoryRow();row.id=String.valueOf(item.Id);row.kind='Salesforce File';
            row.title=item.Title;row.fileType=item.FileType;row.sizeBytes=item.ContentSize;
            row.owner=item.Owner == null ? null : item.Owner.Name;row.uploadedAt=item.CreatedDate;row.modifiedAt=item.LastModifiedDate;
            row.linkedRecords=String.join(links.get(item.Id),'; ');row.libraries=String.join(libraries.get(item.Id),'; ');
            row.relationshipStatus=businessLinked.contains(item.Id) ? 'Business-record link visible'
                : relationshipsComplete ? 'No visible business-record link' : 'Unknown';
            row.completeness=relationshipsComplete && librariesComplete ? 'Visible scope' : 'Partial relationship details';
            page.rows.add(row);
        }
        page.nextCursor=documents[documents.size()-1].Id;
    }
    private static void readAttachments(InventoryPage page, Id afterId) {
        Datetime cutoff=page.startedAt;
        List<Attachment> attachments;
        try {
            if(afterId == null) attachments=[SELECT Id,Name,ContentType,BodyLength,Owner.Name,ParentId,CreatedDate,LastModifiedDate
                FROM Attachment WHERE CreatedDate <= :cutoff WITH USER_MODE ORDER BY Id LIMIT 101];
            else attachments=[SELECT Id,Name,ContentType,BodyLength,Owner.Name,ParentId,CreatedDate,LastModifiedDate
                FROM Attachment WHERE Id > :afterId AND CreatedDate <= :cutoff
                WITH USER_MODE ORDER BY Id LIMIT 101];
        } catch(Exception ex) {
            throw client('Legacy Attachments metadata is unavailable. Check attachment and parent-record read access.');
        }
        page.hasMore=attachments.size()>PAGE_SIZE;
        if(page.hasMore)attachments.remove(PAGE_SIZE);
        for(Attachment item:attachments) {
            InventoryRow row=new InventoryRow();row.id=String.valueOf(item.Id);row.kind='Legacy Attachment';
            row.title=item.Name;row.fileType=item.ContentType;row.sizeBytes=item.BodyLength;
            row.owner=item.Owner == null ? null : item.Owner.Name;row.uploadedAt=item.CreatedDate;row.modifiedAt=item.LastModifiedDate;
            row.linkedRecords=item.ParentId.getSObjectType().getDescribe().getName()+':'+String.valueOf(item.ParentId);
            row.libraries='';row.relationshipStatus='Parent record linked';row.completeness='Visible scope';page.rows.add(row);
        }
        if(!attachments.isEmpty())page.nextCursor=attachments[attachments.size()-1].Id;
    }
    private static AuraHandledException client(String message) {
        AuraHandledException error=new AuraHandledException(message);error.setMessage(message);return error;
    }
}
