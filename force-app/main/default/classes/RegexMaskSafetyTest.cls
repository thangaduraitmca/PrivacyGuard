@IsTest
private class RegexMaskSafetyTest {
    @TestSetup static void packagePermissions() { PrivacyGuardPackageTestAccess.grantAdmin(); }

    private static void rejects(String rule) {
        Boolean blocked=false;
        try { RegexReplaceMaskStrategy.validateRule(rule); }
        catch (RegexReplaceMaskStrategy.InvalidRegexMaskException ex) { blocked=true; }
        System.assert(blocked,'Invalid rule must be rejected.');
    }
    @IsTest static void rejectsMalformedRules() {
        rejects(null); rejects(''); rejects('   '); rejects('[0-9]');
        rejects('=>X'); rejects('   =>X'); rejects('[=>X');
    }
    @IsTest static void validReplacement() {
        System.assertEquals('XXX-XX',new RegexReplaceMaskStrategy().maskValue('123-45','[0-9]=>X','Phone'));
    }
    @IsTest static void emptyReplacementAndDelimiterInReplacement() {
        System.assertEquals('ab',new RegexReplaceMaskStrategy().maskValue('a12b','[0-9]=>','LastName'));
        System.assertEquals('a=>b',new RegexReplaceMaskStrategy().maskValue('x','x=>a=>b','LastName'));
    }
    @IsTest static void nullAndNonmatchingValues() {
        RegexReplaceMaskStrategy strategy=new RegexReplaceMaskStrategy();
        System.assertEquals(null,strategy.maskValue(null,'[0-9]=>X','Phone'));
        System.assertEquals('abc',strategy.maskValue('abc','[0-9]=>X','LastName'));
    }
    @IsTest static void ruleCacheRefreshes() {
        RegexReplaceMaskStrategy strategy=new RegexReplaceMaskStrategy();
        System.assertEquals('X',strategy.maskValue('1','[0-9]=>X','Phone'));
        System.assertEquals('Y',strategy.maskValue('1','[0-9]=>Y','Phone'));
    }
    @IsTest static void invalidReplacementThrowsWithoutEchoingData() {
        Boolean blocked=false;
        try { new RegexReplaceMaskStrategy().maskValue('private-value','(.*)=>$9','LastName'); }
        catch(RegexReplaceMaskStrategy.InvalidRegexMaskException ex) {
            blocked=true; System.assert(!ex.getMessage().contains('private-value'));
        }
        System.assert(blocked);
    }
    @IsTest static void invalidRuleRejectedEvenForNull() {
        Boolean blocked=false;
        try { new RegexReplaceMaskStrategy().maskValue(null,'missing delimiter','Email'); }
        catch(RegexReplaceMaskStrategy.InvalidRegexMaskException ex) { blocked=true; }
        System.assert(blocked);
    }
    @IsTest static void saveRejectsInvalidRule() {
        PrivacyGuardConfigurationController.FieldRow row=new PrivacyGuardConfigurationController.FieldRow();
        row.objectApiName='Contact'; row.fieldApiName='LastName'; row.strategy='REGEX'; row.pattern='[=>X'; row.active=true;
        Boolean blocked=false;
        try { PrivacyGuardConfigurationController.saveConfigurations(new List<PrivacyGuardConfigurationController.FieldRow>{row}); }
        catch(AuraHandledException ex) { blocked=true; }
        System.assert(blocked);
        System.assertEquals(0,[SELECT count() FROM Masking_Field_Config__c WHERE Object_API_Name__c='Contact' AND Field_API_Name__c='LastName']);
    }
    @IsTest static void preflightRejectsMetadataRule() {
        MaskingConfigService.FieldConfig cfg=new MaskingConfigService.FieldConfig();
        cfg.fieldApiName='LastName'; cfg.fieldType='REGEX'; cfg.maskingPattern='bad';
        Boolean blocked=false;
        try { SchemaValidationUtil.validateMaskingTarget(Contact.SObjectType.getDescribe(),cfg); }
        catch(RegexReplaceMaskStrategy.InvalidRegexMaskException ex) { blocked=true; }
        System.assert(blocked);
    }
    @IsTest static void runtimeFailureDoesNotStampOrSavePartialMask() {
        Contact contact=new Contact(LastName='Private',Email='private@example.com'); insert contact;
        MaskingConfigService.FieldConfig nameCfg=new MaskingConfigService.FieldConfig();
        nameCfg.fieldApiName='LastName'; nameCfg.fieldType='STATIC'; nameCfg.maskingPattern='MASKED';
        MaskingConfigService.FieldConfig emailCfg=new MaskingConfigService.FieldConfig();
        emailCfg.fieldApiName='Email'; emailCfg.fieldType='REGEX'; emailCfg.maskingPattern='bad';
        MaskingBatch processor=new MaskingBatch('Regex safety','Contact',new List<MaskingConfigService.FieldConfig>{nameCfg,emailCfg},'Once',null);
        processor.execute(null,new List<SObject>{[SELECT Id,LastName,Email,Data_Masking_Complete__c FROM Contact WHERE Id=:contact.Id]});
        Contact result=[SELECT LastName,Email,Data_Masking_Complete__c FROM Contact WHERE Id=:contact.Id];
        System.assertEquals('Private',result.LastName);
        System.assertEquals('private@example.com',result.Email);
        System.assertEquals(false,result.Data_Masking_Complete__c);
        System.assertEquals(1,processor.getFailedCount());
    }
}
