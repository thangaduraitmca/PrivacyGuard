@IsTest
private class MaskingCompletionServiceTest {
    private static List<MaskingConfigService.FieldConfig> config(String target, String value) {
        MaskingConfigService.FieldConfig f = new MaskingConfigService.FieldConfig();
        f.objectApiName='Contact'; f.fieldApiName=target; f.fieldType='STATIC'; f.maskingPattern=value;
        return new List<MaskingConfigService.FieldConfig>{f};
    }
    @IsTest static void successfulMaskAndSkip() {
        EnvironmentSafetyService.sandboxOverrideForTests=true;
        Contact c=new Contact(LastName='Original'); insert c;
        Test.startTest();
        Database.executeBatch(new MaskingBatch('Checkbox','Contact',config('LastName','MASKED'),'Once',null),200);
        Test.stopTest();
        c=[SELECT LastName,Data_Masking_Complete__c FROM Contact WHERE Id=:c.Id];
        System.assertEquals('MASKED',c.LastName);
        System.assertEquals(true,c.Data_Masking_Complete__c);
    }
    @IsTest static void flaggedRecordSkipped() {
        EnvironmentSafetyService.sandboxOverrideForTests=true;
        Contact c=new Contact(LastName='Keep',Data_Masking_Complete__c=true); insert c;
        Test.startTest();
        Database.executeBatch(new MaskingBatch('Skip','Contact',config('LastName','MASKED'),'Once',null),200);
        Test.stopTest();
        System.assertEquals('Keep',[SELECT LastName FROM Contact WHERE Id=:c.Id].LastName);
    }
    @IsTest static void fullRunAlsoStamps() {
        EnvironmentSafetyService.sandboxOverrideForTests=true;
        Contact c=new Contact(LastName='Original'); insert c;
        Test.startTest();
        Database.executeBatch(new MaskingBatch('Full','Contact',config('LastName','MASKED'),'Full',null),200);
        Test.stopTest();
        c=[SELECT LastName,Data_Masking_Complete__c FROM Contact WHERE Id=:c.Id];
        System.assertEquals('MASKED',c.LastName); System.assertEquals(true,c.Data_Masking_Complete__c);
    }
    @IsTest static void failedDmlDoesNotStamp() {
        EnvironmentSafetyService.sandboxOverrideForTests=true;
        Contact c=new Contact(LastName='Original'); insert c;
        // Invalid email syntax passes text conversion but is rejected by Salesforce DML.
        List<MaskingConfigService.FieldConfig> fields=config('LastName','MASKED');
        fields.addAll(config('Email','not-an-email'));
        MaskingBatch batch=new MaskingBatch('DmlFailure','Contact',fields,'Once',null);
        batch.execute(null,new List<SObject>{[SELECT Id,LastName,Email,Data_Masking_Complete__c FROM Contact WHERE Id=:c.Id]});
        c=[SELECT LastName,Data_Masking_Complete__c FROM Contact WHERE Id=:c.Id];
        System.assertEquals('Original',c.LastName); System.assertEquals(false,c.Data_Masking_Complete__c);
        System.assertEquals(1,batch.getFailedCount());
    }
    @IsTest static void fieldErrorDoesNotPartiallySaveOrStamp() {
        Contact c=new Contact(LastName='Original'); insert c;
        List<MaskingConfigService.FieldConfig> fields=config('LastName','MASKED');
        MaskingConfigService.FieldConfig bad=new MaskingConfigService.FieldConfig();
        bad.objectApiName='Contact'; bad.fieldApiName='Email'; bad.fieldType='UNKNOWN'; fields.add(bad);
        MaskingBatch batch=new MaskingBatch('FieldFailure','Contact',fields,'Once',null);
        batch.execute(null,new List<SObject>{[SELECT Id,LastName,Email,Data_Masking_Complete__c FROM Contact WHERE Id=:c.Id]});
        c=[SELECT LastName,Data_Masking_Complete__c FROM Contact WHERE Id=:c.Id];
        System.assertEquals('Original',c.LastName); System.assertEquals(false,c.Data_Masking_Complete__c);
        System.assertEquals(1,batch.getFailedCount());
    }
    @IsTest static void rejectCompletionAsTarget() {
        EnvironmentSafetyService.sandboxOverrideForTests=true;
        Boolean blocked=false;
        try { new MaskingBatch('Bad','Contact',config('Data_Masking_Complete__c','false'),'Once',null).start(null); }
        catch(SchemaValidationUtil.InvalidSchemaReferenceException ex) { blocked=ex.getMessage().contains('masking target'); }
        System.assert(blocked);
    }
    @IsTest static void resolveStandardObjectsAndRejectTimestamp() {
        for(String obj:new List<String>{'Account','Contact','Lead'}) {
            System.assertNotEquals(null,MaskingCompletionService.requireCheckbox(obj,null));
        }
        Boolean blocked=false;
        try { MaskingCompletionService.requireCheckbox('Contact','Data_Masking_Applied_Date__c'); }
        catch(SchemaValidationUtil.InvalidSchemaReferenceException ex) { blocked=ex.getMessage().contains('Checkbox'); }
        System.assert(blocked);
    }
    @IsTest static void saveAndEditPreserveCheckbox() {
        MaskingJobManagerService.JobInput input=new MaskingJobManagerService.JobInput();
        input.name='Checkbox job'; input.runMode='Once'; input.objects=new List<String>{'Contact'};
        input.id=MaskingJobManagerService.saveJob(input);
        Masking_Job_Object__c first=[SELECT Delta_Tracking_Field__c FROM Masking_Job_Object__c WHERE Masking_Job__c=:input.id];
        input.name='Edited'; MaskingJobManagerService.saveJob(input);
        Masking_Job_Object__c edited=[SELECT Delta_Tracking_Field__c FROM Masking_Job_Object__c WHERE Masking_Job__c=:input.id];
        System.assertEquals(MaskingCompletionService.requireCheckbox('Contact',null),edited.Delta_Tracking_Field__c);
        System.assertEquals(first.Delta_Tracking_Field__c,edited.Delta_Tracking_Field__c);
    }
}
