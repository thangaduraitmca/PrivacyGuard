@IsTest
private class PrivacyGuardSchemaTest {
    @TestSetup static void permissions(){PrivacyGuardPackageTestAccess.grantAdmin();}
    @IsTest static void localAndQualifiedNamesResolveToSameField() {
        Schema.DescribeSObjectResult contactInfo=Contact.SObjectType.getDescribe();
        String canonical=Contact.Data_Masking_Complete__c.getDescribe().getName();
        System.assertEquals(canonical,PrivacyGuardSchema.name(contactInfo,'Data_Masking_Complete__c'));
        System.assertEquals(canonical,PrivacyGuardSchema.name(contactInfo,canonical));
        System.assertEquals(canonical,MaskingCompletionService.requireCheckbox('Contact','Data_Masking_Complete__c'));
        System.assertEquals(null,PrivacyGuardSchema.field(contactInfo,'foreign_namespace__Data_Masking_Complete__c'));
        Boolean rejected=false;
        try{PrivacyGuardSchema.name(contactInfo,'Email FROM User');}catch(SchemaValidationUtil.InvalidSchemaReferenceException ex){rejected=true;}
        System.assert(rejected,'Unknown identifiers must be rejected.');
    }
    @IsTest static void qualifiedAuditQueryExecutesAndIsIdempotent() {
        MaskingLogger.logInfo('PackageSchemaTest','Synthetic audit');
        String queryText='SELECT Id,Job_Name__c FROM Masking_Log__c WITH USER_MODE LIMIT 1';
        String qualified=PrivacyGuardSchema.qualifyQuery(Masking_Log__c.SObjectType,queryText);
        System.assertEquals(qualified,PrivacyGuardSchema.qualifyQuery(Masking_Log__c.SObjectType,qualified));
        List<SObject> records=Database.query(qualified);
        System.assertEquals(1,records.size());
        System.assertEquals('PackageSchemaTest',(String)records[0].get(Masking_Log__c.Job_Name__c));
    }
    @IsTest static void jobFieldsArePresentAndWritableForAdministrator() {
        Schema.SObjectField token=PrivacyGuardSchema.field(Masking_Job__c.SObjectType.getDescribe(),'Job_Name__c');
        System.assertNotEquals(null,token);System.assert(token.getDescribe().isCreateable());
    }
}
