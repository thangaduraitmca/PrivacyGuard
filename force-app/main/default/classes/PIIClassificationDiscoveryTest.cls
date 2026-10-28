@IsTest
private class PIIClassificationDiscoveryTest {
    private static void tags(String objectName,String field,String complianceCategory,String sensitivity) {
        ComplianceCategorizationService.ComplianceInfo info=new ComplianceCategorizationService.ComplianceInfo();info.complianceGroup=complianceCategory;info.securityClassification=sensitivity;
        ComplianceCategorizationService.testTags=new Map<String,Map<String,ComplianceCategorizationService.ComplianceInfo>>{
            objectName=>new Map<String,ComplianceCategorizationService.ComplianceInfo>{field.toLowerCase()=>info}
        };
    }
    @IsTest static void classificationAddsCandidateWithoutConfiguration() {
        tags('Account','NumberOfEmployees','PII','Confidential');
        Integer beforeConfigs=[SELECT count() FROM Masking_Field_Config__c];
        List<PII_Scan_Result__c> rows=PIIFieldScannerService.scanObject('Account','classification-test');
        Boolean found=false;
        for(PII_Scan_Result__c row:rows)if(row.Field_API_Name__c=='NumberOfEmployees'){
            found=true;System.assert(row.Detection_Reason__c.contains('Salesforce Data Classification'));
            System.assert(row.Native_Compliance_Tag__c.contains('PII'));System.assertEquals('New',row.Review_Status__c);
        }
        System.assert(found);System.assertEquals(beforeConfigs,[SELECT count() FROM Masking_Field_Config__c]);
    }
    @IsTest static void sensitivityAloneAddsCandidate() {
        tags('Account','NumberOfEmployees',null,'Restricted');Boolean found=false;
        for(PII_Scan_Result__c row:PIIFieldScannerService.scanObject('Account','restricted-test'))if(row.Field_API_Name__c=='NumberOfEmployees'){
            found=true;System.assert(row.Native_Compliance_Tag__c.contains('Restricted'));
        }
        System.assert(found);
    }
    @IsTest static void configuredFieldsRemainExcluded() {
        tags('Contact','Email','PII','Restricted');
        for(PII_Scan_Result__c row:PIIFieldScannerService.scanObject('Contact','configured-test'))System.assertNotEquals('Email',row.Field_API_Name__c);
    }
    @IsTest static void fieldTypeAndClassificationReasonsAreCombined() {
        tags('Contact','Fax','PII','Confidential');Boolean found=false;
        for(PII_Scan_Result__c row:PIIFieldScannerService.scanObject('Contact','combined-test'))if(row.Field_API_Name__c=='Fax'){
            found=true;System.assert(row.Detection_Reason__c.contains('Field type: Phone'));System.assert(row.Detection_Reason__c.contains('Salesforce Data Classification'));
            PIIScanReviewController.ScanResultRow dto=new PIIScanReviewController.ScanResultRow(row);
            System.assertEquals(row.Native_Compliance_Tag__c,dto.nativeComplianceTag);
        }
        System.assert(found);
    }
    @IsTest static void explicitOptOutDoesNotUseNativeTags() {
        tags('Account','NumberOfEmployees','PII','Restricted');
        for(PII_Scan_Result__c row:PIIFieldScannerService.scanObject('Account','optout-test',false)){
            System.assertEquals(null,row.Native_Compliance_Tag__c);
            System.assert(!row.Detection_Reason__c.contains('Salesforce Data Classification'));
        }
    }
    @IsTest static void lookupFailurePreservesExistingDiscoveryAndLogsWarning() {
        ComplianceCategorizationService.testTags=new Map<String,Map<String,ComplianceCategorizationService.ComplianceInfo>>{'Contact'=>new Map<String,ComplianceCategorizationService.ComplianceInfo>()};
        ComplianceCategorizationService.testWarning='Classification metadata could not be read.';
        Boolean foundFax=false;
        for(PII_Scan_Result__c row:PIIFieldScannerService.scanObject('Contact','lookup-warning'))if(row.Field_API_Name__c=='Fax')foundFax=true;
        System.assert(foundFax);System.assertEquals(1,[SELECT count() FROM Masking_Log__c WHERE Job_Name__c='PII_Classification_lookup-warning']);
    }
}
