@IsTest
private class NumericRangeMaskStrategyTest {
    @IsTest static void generatesWholeNumbersWithinInclusiveBounds(){
        IMaskingStrategy strategy=MaskingStrategyFactory.getStrategy('NUMBER_RANGE',null);
        for(Integer i=0;i<100;i++){
            Decimal value=(Decimal)strategy.maskValue(5,'100|999|0','NumberOfEmployees');
            System.assert(value>=100&&value<=999);System.assertEquals(value.setScale(0),value);
        }
    }
    @IsTest static void decimalNegativeAndFixedRanges(){
        NumericRangeMaskStrategy strategy=new NumericRangeMaskStrategy();
        for(Integer i=0;i<50;i++){
            Decimal value=(Decimal)strategy.maskValue(5,'-10.50|-1.25|2','Numeric');
            System.assert(value>=-10.50&&value<=-1.25);System.assertEquals((value*100).setScale(0),value*100);
        }
        System.assertEquals(Decimal.valueOf('5.25'),strategy.maskValue(5,'5.25|5.25|2','Numeric'));
        System.assertEquals(null,strategy.maskValue(null,'100|999|0','Numeric'));
    }
    @IsTest static void invalidRulesRejected(){
        for(String rule:new List<String>{null,'','100|999','999|100|0','A|100|0','1|10|-1','1|10|19','1.25|9|1','1|10|0|'}){
            Boolean blocked=false;try{NumericRangeMaskStrategy.parseRule(rule);}catch(NumericRangeMaskStrategy.InvalidRangeException ex){blocked=true;}
            System.assert(blocked,'Invalid numeric range must be rejected.');
        }
    }
    @IsTest static void validatesTargetPrecisionAndScale(){
        NumericRangeMaskStrategy.validateRange(Account.NumberOfEmployees.getDescribe(),'100|999|0');
        Boolean blocked=false;try{NumericRangeMaskStrategy.validateRange(Contact.LastName.getDescribe(),'100|999|0');}catch(Exception ex){blocked=true;}System.assert(blocked);
        blocked=false;try{NumericRangeMaskStrategy.validateRange(Account.NumberOfEmployees.getDescribe(),'1|9|2');}catch(Exception ex){blocked=true;}System.assert(blocked);
        blocked=false;try{NumericRangeMaskStrategy.validateRange(Account.NumberOfEmployees.getDescribe(),'1|999999999999999999999|0');}catch(Exception ex){blocked=true;}System.assert(blocked);
    }
    @IsTest static void configurationBlocksReversedRange(){
        PrivacyGuardConfigurationController.FieldRow row=new PrivacyGuardConfigurationController.FieldRow();
        row.objectApiName='Account';row.fieldApiName='NumberOfEmployees';row.strategy='NUMBER_RANGE';row.pattern='999|100|0';row.active=true;
        Boolean blocked=false;try{PrivacyGuardConfigurationController.saveConfigurations(new List<PrivacyGuardConfigurationController.FieldRow>{row});}catch(AuraHandledException ex){blocked=ex.getMessage().contains('Minimum');}System.assert(blocked);
    }
    @IsTest static void batchMasksNumericFieldAndStampsCompletion(){
        EnvironmentSafetyService.sandboxOverrideForTests=true;
        Account account=new Account(Name='Range test',NumberOfEmployees=5);insert account;
        MaskingConfigService.FieldConfig field=new MaskingConfigService.FieldConfig();field.objectApiName='Account';field.fieldApiName='NumberOfEmployees';field.fieldType='NUMBER_RANGE';field.maskingPattern='100|999|0';
        Test.startTest();Database.executeBatch(new MaskingBatch('Range test','Account',new List<MaskingConfigService.FieldConfig>{field},'Once',null),200);Test.stopTest();
        Account result=[SELECT NumberOfEmployees,Data_Masking_Complete__c FROM Account WHERE Id=:account.Id];
        System.assert(result.NumberOfEmployees>=100&&result.NumberOfEmployees<=999);System.assertEquals(true,result.Data_Masking_Complete__c);
    }
    @IsTest static void previewSupportsRangeWithoutWriting(){
        Account account=new Account(Name='Range preview',NumberOfEmployees=5);insert account;
        insert new Masking_Field_Config__c(Object_API_Name__c='Account',Field_API_Name__c='NumberOfEmployees',Masking_Strategy__c='NUMBER_RANGE',Masking_Pattern__c='100|999|0',Is_Active__c=true);
        Masking_Job__c job=new Masking_Job__c(Job_Name__c='Range preview',Run_Mode__c='Full',Execution_Mode__c='Serial',Is_Active__c=true);insert job;
        insert new Masking_Job_Object__c(Masking_Job__c=job.Id,Object_API_Name__c='Account',Sequence__c=1,Is_Active__c=true);
        MaskingPreviewService.PreviewResult preview=MaskingPreviewService.preview(job.Id,'Account');Boolean found=false;
        for(MaskingPreviewService.PreviewRow row:preview.rows)if(row.fieldName=='NumberOfEmployees'){found=true;Decimal value=Decimal.valueOf(row.afterValue);System.assert(value>=100&&value<=999);}
        System.assert(found);System.assertEquals(5,[SELECT NumberOfEmployees FROM Account WHERE Id=:account.Id].NumberOfEmployees);
    }
}
