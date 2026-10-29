/** Bulk configuration auditing. Successful writes and their audit entries commit together. */
public without sharing class PrivacyGuardAuditService {
    public static Boolean isProtectedTrigger(String name) {
        return new Set<String>{'PGAuditMaskingFieldConfig','PGAuditMaskingJob','PGAuditMaskingJobObject'}.contains(name);
    }
    public static String categoryFor(String job,String objectName) {
        String name=job==null?'':job.toLowerCase(); String obj=objectName==null?'':objectName.toLowerCase();
        if(name.startsWith('audit_configuration'))return 'Configuration';
        if(name.startsWith('audit_jobs'))return 'Jobs';
        if(name.startsWith('pii'))return 'PII Discovery';
        if(name.startsWith('automation'))return 'Automation';
        if(name.startsWith('file')||name.startsWith('purge_')||name=='selected_file_deletion'||obj=='contentdocument'||obj=='attachment')return 'Files';
        return 'Data Masking';
    }
    public static void record(String category,String action,Id target,String message) {
        insert new Masking_Log__c(Job_Name__c='Audit_'+category,Activity_Category__c=category,Activity_Action__c=action,
            Record_Id__c=target==null?null:String.valueOf(target),Status__c='Success',Error_Message__c=message);
    }
    public static void recordFailure(String category,String action,Id target,String message) {
        insert new Masking_Log__c(Job_Name__c='Audit_'+category,Activity_Category__c=category,Activity_Action__c=action,
            Record_Id__c=target==null?null:String.valueOf(target),Status__c='Failed',Error_Message__c=message.left(32768));
    }
    public static void capture(String category, List<SObject> records, Map<Id,SObject> prior, String action) {
        if(records==null || records.isEmpty()) return;
        String objectName=records[0].getSObjectType().getDescribe().getName();
        Map<String,Schema.SObjectField> fields=records[0].getSObjectType().getDescribe().fields.getMap();
        List<String> tracked=new List<String>();
        for(String field:fields.keySet()) {
            String key=field.toLowerCase();
            if(key.endsWith('__c') && !key.endsWith('last_run_at__c') && !key.endsWith('last_status__c')) tracked.add(field);
        }
        tracked.sort(); List<Masking_Log__c> logs=new List<Masking_Log__c>();
        for(SObject row:records) {
            SObject old=prior==null?null:prior.get((Id)row.get('Id'));
            Map<String,Object> changes=new Map<String,Object>();
            for(String field:tracked) {
                Object oldValue=(action=='Created'||action=='Restored')?null:old==null?row.get(field):old.get(field);
                Object newValue=action=='Deleted'?null:row.get(field);
                if(action=='Updated' && JSON.serialize(oldValue)==JSON.serialize(newValue)) continue;
                // Static replacements/patterns may contain sensitive values; record the change without copying them.
                Boolean secret=field.toLowerCase().endsWith('masking_pattern__c');
                changes.put(field,new Map<String,Object>{'before'=>secret&&oldValue!=null?'[redacted]':oldValue,'after'=>secret&&newValue!=null?'[redacted]':newValue});
            }
            if(changes.isEmpty()) continue;
            String targetObject=objectName;String targetField;
            if(row instanceof Masking_Field_Config__c){Masking_Field_Config__c config=(Masking_Field_Config__c)row;targetObject=config.Object_API_Name__c;targetField=config.Field_API_Name__c;}
            else if(row instanceof Masking_Job_Object__c)targetObject=((Masking_Job_Object__c)row).Object_API_Name__c;
            logs.add(new Masking_Log__c(Job_Name__c='Audit_'+category,Activity_Category__c=category,
                Activity_Action__c=action,Object_API_Name__c=targetObject,Field_API_Name__c=targetField,Record_Id__c=String.valueOf(row.get('Id')),
                Status__c='Success',Error_Message__c=action+' '+objectName+' configuration.',Change_Details__c=JSON.serialize(changes)));
        }
        // System-context write is intentional: normal configuration editors cannot forge audit fields.
        // Any persistence failure rolls back the originating configuration transaction.
        if(!logs.isEmpty()) insert logs;
    }
}
