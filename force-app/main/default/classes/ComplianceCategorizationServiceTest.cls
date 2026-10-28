@IsTest
private class ComplianceCategorizationServiceTest {
    private static ComplianceCategorizationService.ComplianceInfo info(String compliance,String sensitivity) {
        ComplianceCategorizationService.ComplianceInfo value=new ComplianceCategorizationService.ComplianceInfo();
        value.complianceGroup=compliance;value.securityClassification=sensitivity;return value;
    }
    @IsTest static void sensitiveTagsAndLowSensitivityLevels() {
        for(String sensitivity:new List<String>{'Confidential','Restricted','MissionCritical','Mission Critical','PII'})
            System.assert(ComplianceCategorizationService.isSensitive(info(null,sensitivity)));
        System.assert(!ComplianceCategorizationService.isSensitive(info(null,'Public')));
        System.assert(!ComplianceCategorizationService.isSensitive(info(null,'Internal')));
        System.assert(!ComplianceCategorizationService.isSensitive(null));
        System.assert(ComplianceCategorizationService.isSensitive(info('GDPR;PII','Public')));
    }
    @IsTest static void displaysTagsAndLimitsLength() {
        System.assertEquals('Compliance: PII | Sensitivity: Confidential',ComplianceCategorizationService.describeTags(info('PII','Confidential')));
        String large='';for(Integer i=0;i<300;i++)large+='x';
        System.assert(ComplianceCategorizationService.describeTags(info(large,'Restricted')).length()<=255);
    }
    @IsTest static void unknownObjectReturnsWarning() {
        System.assert(ComplianceCategorizationService.getComplianceTags('Not_A_Real_Object__x').isEmpty());
        System.assertNotEquals(null,ComplianceCategorizationService.getLastWarning());
    }
    @IsTest static void nativeLookupPerformsNoCallouts() {
        Integer beforeCallouts=Limits.getCallouts();
        Map<String,ComplianceCategorizationService.ComplianceInfo> tags=ComplianceCategorizationService.getComplianceTags('Contact');
        System.assertNotEquals(null,tags);System.assertEquals(beforeCallouts,Limits.getCallouts());
    }
}
