@IsTest
private class NullMaskStrategyTest {
    private static MaskingConfigService.FieldConfig field(String api) {
        MaskingConfigService.FieldConfig f=new MaskingConfigService.FieldConfig();
        f.objectApiName='Contact'; f.fieldApiName=api; f.fieldType='NULL'; return f;
    }
    @IsTest static void nullableFieldsCanBeCleared() {
        SchemaValidationUtil.validateMaskingStrategy(Contact.Email.getDescribe(),'NULL');
        SchemaValidationUtil.validateMaskingStrategy(Contact.Birthdate.getDescribe(),'NULL');
        SchemaValidationUtil.validateMaskingTarget(Contact.SObjectType.getDescribe(),field('Birthdate'));
        System.assertEquals(null,MaskingStrategyFactory.getStrategy('NULL',null).maskValue('private',null,'Email'));
    }
    @IsTest static void saveBlocksRequiredField() {
        PrivacyGuardConfigurationController.FieldRow row=new PrivacyGuardConfigurationController.FieldRow();
        row.objectApiName='Contact'; row.fieldApiName='LastName'; row.strategy='NULL'; row.active=true;
        Boolean blocked=false;
        try { PrivacyGuardConfigurationController.saveConfigurations(new List<PrivacyGuardConfigurationController.FieldRow>{row}); }
        catch(AuraHandledException ex) { blocked=ex.getMessage().contains('required field'); }
        System.assert(blocked,'Required field must be rejected when saving the configuration.');
    }
    @IsTest static void optionalFieldConfigurationSavesWithoutPattern() {
        PrivacyGuardConfigurationController.FieldRow row=new PrivacyGuardConfigurationController.FieldRow();
        row.objectApiName='Contact'; row.fieldApiName='OtherPostalCode'; row.strategy='NULL'; row.pattern='old pattern'; row.active=true;
        PrivacyGuardConfigurationController.saveConfigurations(new List<PrivacyGuardConfigurationController.FieldRow>{row});
        Masking_Field_Config__c saved=[SELECT Masking_Strategy__c,Masking_Pattern__c FROM Masking_Field_Config__c WHERE Object_API_Name__c='Contact' AND Field_API_Name__c='OtherPostalCode' LIMIT 1];
        System.assertEquals('NULL',saved.Masking_Strategy__c);System.assertEquals(null,saved.Masking_Pattern__c);
    }
    @IsTest static void batchClearsTextAndDateAndMarksComplete() {
        EnvironmentSafetyService.sandboxOverrideForTests=true;
        Contact person=new Contact(LastName='Keep',Email='private@example.com',Birthdate=Date.newInstance(2000,1,1));insert person;
        Test.startTest();
        Database.executeBatch(new MaskingBatch('Clear','Contact',new List<MaskingConfigService.FieldConfig>{field('Email'),field('Birthdate')},'Once',null),200);
        Test.stopTest();
        Contact result=[SELECT LastName,Email,Birthdate,Data_Masking_Complete__c FROM Contact WHERE Id=:person.Id];
        System.assertEquals('Keep',result.LastName);System.assertEquals(null,result.Email);System.assertEquals(null,result.Birthdate);
        System.assertEquals(true,result.Data_Masking_Complete__c);
    }
    @IsTest static void preflightBlocksRequiredField() {
        Boolean blocked=false;
        try {SchemaValidationUtil.validateMaskingTarget(Contact.SObjectType.getDescribe(),field('LastName'));}
        catch(SchemaValidationUtil.InvalidSchemaReferenceException ex) {blocked=ex.getMessage().contains('required field');}
        System.assert(blocked);
    }
    @IsTest static void runtimeRequiredFieldFailureDoesNotStamp() {
        Contact person=new Contact(LastName='Keep');insert person;
        MaskingBatch batch=new MaskingBatch('Reject required','Contact',new List<MaskingConfigService.FieldConfig>{field('LastName')},'Once',null);
        batch.execute(null,new List<SObject>{[SELECT Id,LastName,Data_Masking_Complete__c FROM Contact WHERE Id=:person.Id]});
        Contact result=[SELECT LastName,Data_Masking_Complete__c FROM Contact WHERE Id=:person.Id];
        System.assertEquals('Keep',result.LastName);System.assertEquals(false,result.Data_Masking_Complete__c);
        System.assertEquals(1,batch.getFailedCount());
    }
    @IsTest static void staticLiteralNullRemainsText() {
        System.assertEquals('NULL',new StaticValueMaskStrategy().maskValue('original','NULL','OtherPostalCode'));
    }
}
