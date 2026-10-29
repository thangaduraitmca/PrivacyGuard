/** Verifies persisted configuration and keyword lifecycle through public APIs. */
@IsTest
private class PrivacyGuardConfigLifecycleTest {
    @TestSetup static void packagePermissions() { PrivacyGuardPackageTestAccess.grantAdmin(); }

    private static PrivacyGuardConfigurationController.FieldRow row(String field,String strategy,String pattern) {
        PrivacyGuardConfigurationController.FieldRow r=new PrivacyGuardConfigurationController.FieldRow();
        r.objectApiName='Contact';r.fieldApiName=field;r.strategy=strategy;r.pattern=pattern;r.active=true;return r;
    }
    @IsTest static void configurationCreateUpdateListDelete() {
        Test.startTest();
        PrivacyGuardConfigurationController.saveConfigurations(new List<PrivacyGuardConfigurationController.FieldRow>{row('Email','static','masked@example.invalid')});
        PrivacyGuardConfigurationController.saveConfigurations(new List<PrivacyGuardConfigurationController.FieldRow>{row('Email','STATIC','updated@example.invalid')});
        List<PrivacyGuardConfigurationController.FieldRow> saved=PrivacyGuardConfigurationController.getConfigurations();
        System.assertEquals(1,saved.size(),'Saving the same field must update rather than duplicate it.');
        System.assertEquals('updated@example.invalid',saved[0].pattern);
        System.assertEquals('STATIC',saved[0].strategy);
        System.assertEquals('Manual',saved[0].source);
        System.assertEquals(false,saved[0].unsupported);
        System.assert(!PrivacyGuardConfigurationController.getObjects().isEmpty());
        System.assert(!PrivacyGuardConfigurationController.getEligibleFields('Contact').isEmpty());
        System.assertEquals(0,PrivacyGuardConfigurationController.getEligibleFields(null).size());
        PrivacyGuardConfigurationController.deleteConfigurations(new List<Id>{saved[0].id});
        Test.stopTest();
        System.assertEquals(0,[SELECT COUNT() FROM Masking_Field_Config__c]);
    }
    @IsTest static void invalidConfigurationDoesNotPersist() {
        Boolean rejected=false;
        try {PrivacyGuardConfigurationController.saveConfigurations(new List<PrivacyGuardConfigurationController.FieldRow>{row('Email','STATIC',null)});}
        catch(AuraHandledException ex){rejected=true;System.assert(ex.getMessage().contains('static replacement'));}
        System.assert(rejected,'Active STATIC configuration requires a replacement.');
        rejected=false;
        try {PrivacyGuardConfigurationController.saveConfigurations(new List<PrivacyGuardConfigurationController.FieldRow>{row('LeadSource','STATIC','Other')});}
        catch(AuraHandledException ex){rejected=true;System.assert(ex.getMessage().contains('not supported'));}
        System.assert(rejected,'Picklist masking must be rejected.');
        System.assertEquals(0,[SELECT COUNT() FROM Masking_Field_Config__c]);
    }
    @IsTest static void orgKeywordLifecycleAndDefaultExclusion() {
        Test.startTest();
        PrivacyGuardConfigurationController.saveKeyword(null,'pg_unique_secret_token',true,'Initial');
        PII_Keyword_Config__c keyword=[SELECT Id FROM PII_Keyword_Config__c WHERE Keyword__c='pg_unique_secret_token'];
        Boolean rejected=false;
        try {PrivacyGuardConfigurationController.saveKeyword(null,'PG-UNIQUE-SECRET-TOKEN',true,null);}
        catch(AuraHandledException ex){rejected=true;System.assert(ex.getMessage().contains('already exists'));}
        System.assert(rejected,'Normalised duplicate keywords must be rejected.');
        PrivacyGuardConfigurationController.saveKeyword(keyword.Id,'pg_unique_secret_token',true,'Updated');
        Boolean visible=false;
        for(PrivacyGuardConfigurationController.KeywordRow r:PrivacyGuardConfigurationController.getKeywords()) {
            if(r.id==keyword.Id){visible=true;System.assertEquals('Updated',r.notes);System.assertEquals(true,r.editable);}
        }
        System.assert(visible);
        PrivacyGuardConfigurationController.deleteKeyword(keyword.Id,null,false);
        System.assertEquals(0,[SELECT COUNT() FROM PII_Keyword_Config__c WHERE Id=:keyword.Id]);
        PII_Keyword__mdt packaged=[SELECT Keyword__c FROM PII_Keyword__mdt WHERE Keyword__c != null LIMIT 1];
        PrivacyGuardConfigurationController.deleteKeyword(null,packaged.Keyword__c,true);
        PrivacyGuardConfigurationController.deleteKeyword(null,packaged.Keyword__c,true);
        for(PrivacyGuardConfigurationController.KeywordRow r:PrivacyGuardConfigurationController.getKeywords())
            System.assertNotEquals(packaged.Keyword__c,r.keyword,'Excluded defaults must stay hidden.');
        Test.stopTest();
        System.assertEquals(1,[SELECT COUNT() FROM PII_Keyword_Config__c WHERE Is_Active__c=false]);
    }
}
