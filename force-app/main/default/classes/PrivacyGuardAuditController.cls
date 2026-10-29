/** Permission-gated, user-mode Audit Centre queries with stable keyset pagination. */
public with sharing class PrivacyGuardAuditController {
    public class Row {
        @AuraEnabled public Id id;
        @AuraEnabled public Datetime occurredAt;
        @AuraEnabled public String userName;
        @AuraEnabled public String source;
        @AuraEnabled public String status;
        @AuraEnabled public String category;
        @AuraEnabled public String action;
        @AuraEnabled public String target;
        @AuraEnabled public String field;
        @AuraEnabled public String recordId;
        @AuraEnabled public String message;
        @AuraEnabled public String changes;
        @AuraEnabled public String classification;
    }
    public class AuditPage {
        @AuraEnabled public List<Row> rows;
        @AuraEnabled public Boolean hasMore;
        @AuraEnabled public Datetime cutoff;
        @AuraEnabled public Datetime nextTime;
        @AuraEnabled public Id nextId;
    }
    @AuraEnabled
    public static AuditPage load(String category,String status,String search,String actor,Date fromDate,Date toDate,Datetime cursorTime,Id cursorId,Datetime cutoff) {
        if(!PrivacyGuardSecurityService.hasPermission('View_PrivacyGuard_Audit')) throw client('Audit access is required. Ask your administrator to assign View PrivacyGuard Audit.');
        Set<String> categories=new Set<String>{'All','Data Masking','PII Discovery','Automation','Files','Configuration','Jobs'};
        if(!categories.contains(category)) throw client('Choose a valid activity category.');
        if(status!='All' && status!='Success' && status!='Failed') throw client('Choose a valid status.');
        if((cursorTime==null)!=(cursorId==null)) throw client('Invalid page cursor. Refresh the audit view.');
        Date first=fromDate==null?Date.today().addDays(-30):fromDate;
        Date last=toDate==null?Date.today():toDate;
        if(first>last) throw client('Start date must be on or before end date.');
        Datetime startAt=Datetime.newInstance(first,Time.newInstance(0,0,0,0));
        Datetime endAt=Datetime.newInstance(last.addDays(1),Time.newInstance(0,0,0,0));
        Datetime snapshot=cutoff==null?System.now():cutoff;
        String term='%'+(search==null?'':search.trim())+'%'; String who='%'+(actor==null?'':actor.trim())+'%';
        String q='SELECT Id,Name,CreatedDate,CreatedById,CreatedBy.Name,Job_Name__c,Status__c,Object_API_Name__c,Field_API_Name__c,Record_Id__c,Activity_Category__c,Activity_Action__c FROM Masking_Log__c WHERE CreatedDate >= :startAt AND CreatedDate < :endAt AND CreatedDate <= :snapshot';
        String pii='(Job_Name__c LIKE \'PII%\')';
        String automation='(Job_Name__c LIKE \'Automation%\')';
        String files='(Job_Name__c LIKE \'File%\' OR Job_Name__c LIKE \'Purge_%\' OR Job_Name__c = \'Selected_File_Deletion\')';
        String legacy;
        if(category=='PII Discovery') legacy=pii;
        else if(category=='Automation') legacy=automation;
        else if(category=='Files') legacy=files;
        else if(category=='Data Masking') legacy='(NOT ('+pii+' OR '+automation+' OR '+files+'))';
        if(category!='All') {
            q+=' AND (Activity_Category__c = :category';
            if(legacy!=null) q+=' OR (Activity_Category__c = null AND '+legacy+')';
            q+=')';
        }
        if(status!='All') q+=' AND Status__c = :status';
        if(!String.isBlank(search)) q+=' AND (Job_Name__c LIKE :term OR Object_API_Name__c LIKE :term OR Field_API_Name__c LIKE :term OR Record_Id__c LIKE :term)';
        if(!String.isBlank(actor)) q+=' AND CreatedBy.Name LIKE :who';
        if(cursorTime!=null) q+=' AND (CreatedDate < :cursorTime OR (CreatedDate = :cursorTime AND Id < :cursorId))';
        q+=' WITH USER_MODE ORDER BY CreatedDate DESC,Id DESC LIMIT 101';
        AuditPage page=new AuditPage(); List<Masking_Log__c> logs;
        try { logs=Database.query(PrivacyGuardSchema.qualifyQuery(Masking_Log__c.SObjectType,q)); }
        catch(Exception ex) {
            System.debug(LoggingLevel.ERROR,'PrivacyGuard Audit query failed: '+ex.getMessage());
            if(Test.isRunningTest())throw client('Audit query failed: '+ex.getMessage());
            throw client('Audit records could not be read. Verify Masking Log object and field read permissions.');
        }
        page.cutoff=snapshot;page.hasMore=logs.size()>100;
        if(page.hasMore)logs.remove(100);
        page.rows=new List<Row>();for(Masking_Log__c log:logs)page.rows.add(convert(log));
        if(!logs.isEmpty()){Masking_Log__c tail=logs[logs.size()-1];page.nextTime=tail.CreatedDate;page.nextId=tail.Id;}
        return page;
    }
    @AuraEnabled public static Row detail(Id logId) {
        if(!PrivacyGuardSecurityService.hasPermission('View_PrivacyGuard_Audit'))throw client('Audit access is required.');
        List<Masking_Log__c> logs=[SELECT Id,CreatedDate,CreatedBy.Name,Job_Name__c,Status__c,Object_API_Name__c,Field_API_Name__c,Record_Id__c,Activity_Category__c,Activity_Action__c,Error_Message__c,Change_Details__c FROM Masking_Log__c WHERE Id=:logId WITH USER_MODE LIMIT 1];
        if(logs.isEmpty())throw client('This audit record is unavailable.');
        Row row=convert(logs[0]);row.message=logs[0].Error_Message__c;row.changes=logs[0].Change_Details__c;return row;
    }
    private static Row convert(Masking_Log__c log) {
        Row row=new Row();row.id=log.Id;row.occurredAt=log.CreatedDate;row.userName=log.CreatedBy.Name;
        row.source=log.Job_Name__c;row.status=log.Status__c;row.target=log.Object_API_Name__c;
        row.field=log.Field_API_Name__c;row.recordId=log.Record_Id__c;row.action=log.Activity_Action__c;
        row.category=String.isBlank(log.Activity_Category__c)?PrivacyGuardAuditService.categoryFor(log.Job_Name__c,log.Object_API_Name__c):log.Activity_Category__c;
        row.classification=String.isBlank(log.Activity_Category__c)?'Inferred from legacy source':'Recorded category';return row;
    }
    private static AuraHandledException client(String text){AuraHandledException ex=new AuraHandledException(text);ex.setMessage(text);return ex;}
}
