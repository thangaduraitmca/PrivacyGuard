@IsTest
private class ListMaskStrategyTest {
    @IsTest static void trimsDeduplicatesAndPicksOnlyConfiguredValues(){
        System.assertEquals(new List<String>{'Morgan','Jordan'},ListMaskStrategy.parseValues(' Morgan | Jordan | Morgan '));
        IMaskingStrategy strategy=MaskingStrategyFactory.getStrategy('LIST',null);
        for(Integer i=0;i<30;i++)System.assert(new Set<String>{'Morgan','Jordan'}.contains((String)strategy.maskValue('Private','Morgan|Jordan','LastName')));
        System.assertEquals(null,strategy.maskValue(null,'Morgan|Jordan','LastName'));
        System.assertEquals('Taylor',strategy.maskValue('Private','Taylor','LastName'));
    }
    @IsTest static void rejectsBlankEntriesAndOverlongRules(){
        String longRule='';for(Integer i=0;i<256;i++)longRule+='x';
        for(String rule:new List<String>{null,'',' ','|Morgan','Morgan|','Morgan||Jordan',longRule}){
            Boolean blocked=false;try{ListMaskStrategy.parseValues(rule);}catch(ListMaskStrategy.InvalidListException ex){blocked=true;}
            System.assert(blocked);
        }
    }
    @IsTest static void rejectsWrongTypeAndOversizedValue(){
        Boolean blocked=false;try{ListMaskStrategy.validateValues(Contact.Birthdate.getDescribe(),'2020-01-01');}catch(ListMaskStrategy.InvalidListException ex){blocked=true;}System.assert(blocked);
        String tooLong='';for(Integer i=0;i<81;i++)tooLong+='x';
        blocked=false;try{ListMaskStrategy.validateValues(Contact.LastName.getDescribe(),tooLong);}catch(ListMaskStrategy.InvalidListException ex){blocked=true;}System.assert(blocked);
    }
    @IsTest static void configurationRejectsInvalidList(){
        PrivacyGuardConfigurationController.FieldRow row=new PrivacyGuardConfigurationController.FieldRow();
        row.objectApiName='Contact';row.fieldApiName='LastName';row.strategy='LIST';row.pattern='Morgan||Jordan';row.active=true;
        Boolean blocked=false;try{PrivacyGuardConfigurationController.saveConfigurations(new List<PrivacyGuardConfigurationController.FieldRow>{row});}catch(AuraHandledException ex){blocked=true;}System.assert(blocked);
    }
    @IsTest static void batchUsesListAndMarksCompletion(){
        EnvironmentSafetyService.sandboxOverrideForTests=true;
        Contact person=new Contact(LastName='Private');insert person;
        MaskingConfigService.FieldConfig cfg=new MaskingConfigService.FieldConfig();cfg.objectApiName='Contact';cfg.fieldApiName='LastName';cfg.fieldType='LIST';cfg.maskingPattern='Morgan|Jordan';
        Test.startTest();Database.executeBatch(new MaskingBatch('List test','Contact',new List<MaskingConfigService.FieldConfig>{cfg},'Once',null),200);Test.stopTest();
        Contact result=[SELECT LastName,Data_Masking_Complete__c FROM Contact WHERE Id=:person.Id];
        System.assert(new Set<String>{'Morgan','Jordan'}.contains(result.LastName));System.assertEquals(true,result.Data_Masking_Complete__c);
    }
    @IsTest static void previewSupportsListWithoutWriting(){
        Contact person=new Contact(LastName='Private');insert person;
        insert new Masking_Field_Config__c(Object_API_Name__c='Contact',Field_API_Name__c='LastName',Masking_Strategy__c='LIST',Masking_Pattern__c='Morgan|Jordan',Is_Active__c=true);
        Masking_Job__c job=new Masking_Job__c(Job_Name__c='List preview',Run_Mode__c='Full',Execution_Mode__c='Serial',Is_Active__c=true);insert job;
        insert new Masking_Job_Object__c(Masking_Job__c=job.Id,Object_API_Name__c='Contact',Sequence__c=1,Is_Active__c=true);
        MaskingPreviewService.PreviewResult result=MaskingPreviewService.preview(job.Id,'Contact');Boolean found=false;
        for(MaskingPreviewService.PreviewRow row:result.rows)if(row.fieldName=='LastName'){found=true;System.assert(new Set<String>{'Morgan','Jordan'}.contains(row.afterValue));}
        System.assert(found);System.assertEquals('Private',[SELECT LastName FROM Contact WHERE Id=:person.Id].LastName);
    }
}
