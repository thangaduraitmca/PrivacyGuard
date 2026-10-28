/** Read-only masking examples. No DML, automation toggles, or job execution. */
public with sharing class MaskingPreviewService {
    public class PreviewRow {
        @AuraEnabled public String key {get;set;}
        @AuraEnabled public String recordId {get;set;}
        @AuraEnabled public String fieldName {get;set;}
        @AuraEnabled public String strategy {get;set;}
        @AuraEnabled public String beforeValue {get;set;}
        @AuraEnabled public String afterValue {get;set;}
        @AuraEnabled public String outcome {get;set;}
    }
    public class PreviewResult {
        @AuraEnabled public List<PreviewRow> rows {get;set;}
        @AuraEnabled public Integer sampleCount {get;set;}
    }
    private static final Map<String,String> BUILT_INS = new Map<String,String>{
        'EMAIL'=>'EmailMaskStrategy','EMAIL_INVALID'=>'InvalidEmailMaskStrategy',
        'PHONE'=>'PhoneMaskStrategy','NAME'=>'NameMaskStrategy',
        'RANDOM_STRING'=>'RandomStringMaskStrategy','STATIC'=>'StaticValueMaskStrategy',
        'NUMBER_RANGE'=>'NumericRangeMaskStrategy','REGEX'=>'RegexReplaceMaskStrategy','NULL'=>'NullMaskStrategy','LIST'=>'ListMaskStrategy'
    };
    @AuraEnabled public static PreviewResult preview(Id jobId, String objectApiName) {
        PrivacyGuardSecurityService.requireRunPermission();
        if (jobId == null || String.isBlank(objectApiName)) throw error('Select a job and object to preview.');
        Masking_Job__c job=[SELECT Run_Mode__c FROM Masking_Job__c WHERE Id=:jobId LIMIT 1];
        List<Masking_Job_Object__c> selected=[SELECT Delta_Tracking_Field__c FROM Masking_Job_Object__c
            WHERE Masking_Job__c=:jobId AND Object_API_Name__c=:objectApiName AND Is_Active__c=true LIMIT 1];
        if (selected.isEmpty()) throw error('This object is not active in the selected job.');
        if (job.Run_Mode__c!='Full' && job.Run_Mode__c!='Once') throw error('Choose Full or Unmasked records only before previewing this job.');
        Schema.DescribeSObjectResult obj=SchemaValidationUtil.requireValidObject(objectApiName);
        if (!obj.isAccessible()) throw error('You do not have read access to this object.');
        List<MaskingConfigService.FieldConfig> configs=MaskingConfigService.getActiveFieldConfigsByObject().get(objectApiName);
        if(configs==null||configs.isEmpty()) throw error('No active masking fields are configured.');
        if(configs.size()>100) throw error('Preview supports up to 100 configured fields per object.');
        String flag=MaskingCompletionService.requireCheckbox(objectApiName,selected[0].Delta_Tracking_Field__c);
        Set<String> names=new Set<String>{'Id'};
        for(MaskingConfigService.FieldConfig cfg:configs) {
            SchemaValidationUtil.validateMaskingTarget(obj,cfg);
            Schema.DescribeFieldResult field=obj.fields.getMap().get(cfg.fieldApiName).getDescribe();
            if(!field.isAccessible()) throw error('Preview requires read access to '+objectApiName+'.'+cfg.fieldApiName+'.');
            String kind=cfg.fieldType.toUpperCase();
            String builtIn=BUILT_INS.get(kind);
            // Never invoke subscriber custom strategy code in a read-only preview.
            if(builtIn==null || (String.isNotBlank(cfg.strategyClass) &&
                !cfg.strategyClass.equalsIgnoreCase(builtIn) &&
                !cfg.strategyClass.equalsIgnoreCase('privacyguard.'+builtIn))) {
                throw error('Preview supports built-in strategies only. Review '+cfg.fieldApiName+'.');
            }
            names.add(field.getName());
        }
        String soql='SELECT '+String.join(new List<String>(names),',')+' FROM '+obj.getName();
        if(job.Run_Mode__c=='Once') {
            if(!obj.fields.getMap().get(flag).getDescribe().isAccessible()) throw error('Read access to the completion checkbox is required for preview.');
            soql+=' WHERE '+flag+' = false';
        }
        // USER_MODE enforces sharing and field permissions, including the filter field.
        soql+=' WITH USER_MODE ORDER BY Id LIMIT 5';
        List<SObject> records=Database.query(soql);
        PreviewResult result=new PreviewResult();result.rows=new List<PreviewRow>();result.sampleCount=records.size();
        Map<Integer,IMaskingStrategy> strategies=new Map<Integer,IMaskingStrategy>();
        for(SObject record:records) {
            for(Integer i=0;i<configs.size();i++) {
                MaskingConfigService.FieldConfig cfg=configs[i];
                PreviewRow row=new PreviewRow();row.recordId=String.valueOf(record.Id);
                row.key=row.recordId+':'+String.valueOf(i);row.fieldName=cfg.fieldApiName;row.strategy=cfg.fieldType;
                Object before=record.get(cfg.fieldApiName);row.beforeValue=display(before);
                try {
                    if(!strategies.containsKey(i)) strategies.put(i,MaskingStrategyFactory.getStrategy(cfg.fieldType,null));
                    Object after=cfg.fieldType.equalsIgnoreCase('STATIC')
                        ? SchemaValidationUtil.convertStaticMaskValue(obj.fields.getMap().get(cfg.fieldApiName).getDescribe(),cfg.maskingPattern)
                        : strategies.get(i).maskValue(before,cfg.maskingPattern,cfg.fieldApiName);
                    if(cfg.fieldType.equalsIgnoreCase('NUMBER_RANGE')) after=NumericRangeMaskStrategy.convertForField(obj.fields.getMap().get(cfg.fieldApiName).getDescribe(),after);
                    row.afterValue=display(after);
                    row.outcome=before==null&&after==null?'Already empty':
                        (String.valueOf(before)==String.valueOf(after)?'Unchanged — review rule':'Changed');
                } catch(Exception ex) {
                    row.afterValue='Preview unavailable';row.outcome='Error — review masking rule';
                }
                result.rows.add(row);
            }
        }
        return result;
    }
    private static String display(Object value) {
        if(value==null)return '(NULL)';
        String text=String.valueOf(value);
        return text.length()>500?text.substring(0,500)+' [truncated]':text;
    }
    private static AuraHandledException error(String message) {
        AuraHandledException ex=new AuraHandledException(message);ex.setMessage(message);return ex;
    }
}
