/**
 * @class         MaskingJobOrchestratorTest
 * @description   Apex test class for the PrivacyGuard managed package. See the implementation comments below for functional and security design details.
 * @package       PrivacyGuard
 * @namespace     privacyguard
 * @apiVersion    66.0
 * @owner         PrivacyGuard Engineering
 * @changeControl Changes to this class must be peer reviewed, linked to an approved work item, validated by automated tests, and promoted through the managed-package release process.
 *
 * CHANGE HISTORY
 * Version     Date         Change Ref         Author/Owner               Description
 * 1.0.0       2026-09-16   PG-BASELINE-001    PrivacyGuard Engineering   Established managed-package audit and change-control baseline.
 */
/**
 * Uses the sample package config (Mask_Contact, Sequence_Order 1; Mask_Lead,
 * Sequence_Order 2 - both Serial) to prove real serial chaining across two
 * different jobs/objects, plus the ad-hoc/skip branches that don't depend on CMDT.
 */
@isTest
private with sharing class MaskingJobOrchestratorTest {

    @testSetup
    static void setup() {
        insert new Contact(LastName = 'OriginalLastName', Email = 'contact@example.com', Phone = '415-555-0100');
        insert new Lead(LastName = 'OriginalLead', Company = 'RealCompanyName', Email = 'lead@example.com', Phone = '415-555-0200');
    }

    @isTest
    static void testSerialChainMasksBothConfiguredObjectsInSequence() {
        EnvironmentSafetyService.sandboxOverrideForTests = true;

        Test.startTest();
        MaskingFrameworkService.executeMaskingRun();
        Test.stopTest();

        Contact c = [SELECT LastName FROM Contact LIMIT 1];
        Lead l = [SELECT Company, Email FROM Lead LIMIT 1];

        System.assertNotEquals('OriginalLastName', c.LastName, 'First serial job (Mask_Contact) should have run');
        System.assertNotEquals('RealCompanyName', l.Company, 'Second serial job (Mask_Lead) should have run after the first');
        System.assertNotEquals('lead@example.com', l.Email);

        Automation_Bypass__c settings = Automation_Bypass__c.getOrgDefaults();
        System.assertEquals(false, settings.Bypass_All_Automations__c,
            'Automations should be re-enabled only after every job in the chain completes');
    }

    @isTest
    static void testRunJobsWithNullOrEmptyListIsANoOp() {
        EnvironmentSafetyService.sandboxOverrideForTests = true;

        Test.startTest();
        MaskingJobOrchestrator.runJobs(null);
        MaskingJobOrchestrator.runJobs(new List<MaskingConfigService.JobConfig>());
        Test.stopTest();

        Contact c = [SELECT LastName FROM Contact LIMIT 1];
        System.assertEquals('OriginalLastName', c.LastName, 'Nothing should run for an empty/null job list');
    }

    @isTest
    static void testAdHocParallelJobWithNoFieldConfigIsSkippedButOthersStillRun() {
        EnvironmentSafetyService.sandboxOverrideForTests = true;

        MaskingConfigService.JobConfig validJob = new MaskingConfigService.JobConfig();
        validJob.jobName = 'AdHoc_Mask_Contact';
        validJob.objectApiName = 'Contact';
        validJob.executionMode = 'Parallel';
        validJob.sequenceOrder = 1;
        validJob.batchSize = 200;
        validJob.runMode = 'Full';
        validJob.jobType = 'FIELD_MASKING';

        // Opportunity has no Masking_Configuration__mdt entries in this package, so
        // buildBatchable() should log-and-skip this one rather than throwing.
        MaskingConfigService.JobConfig unconfiguredJob = new MaskingConfigService.JobConfig();
        unconfiguredJob.jobName = 'AdHoc_Mask_Opportunity';
        unconfiguredJob.objectApiName = 'Opportunity';
        unconfiguredJob.executionMode = 'Parallel';
        unconfiguredJob.sequenceOrder = 2;
        unconfiguredJob.batchSize = 200;
        unconfiguredJob.runMode = 'Full';
        unconfiguredJob.jobType = 'FIELD_MASKING';

        Test.startTest();
        MaskingJobOrchestrator.runJobs(new List<MaskingConfigService.JobConfig>{ validJob, unconfiguredJob });
        Test.stopTest();

        Contact c = [SELECT LastName FROM Contact LIMIT 1];
        System.assertNotEquals('OriginalLastName', c.LastName, 'The valid parallel job should still have run');

        // The tracker should still reach completion (both jobs counted, one skipped
        // immediately) and re-enable automations rather than getting stuck.
        Automation_Bypass__c settings = Automation_Bypass__c.getOrgDefaults();
        System.assertEquals(false, settings.Bypass_All_Automations__c);

        List<Masking_Log__c> skipLogs = [
            SELECT Error_Message__c FROM Masking_Log__c
            WHERE Object_API_Name__c = 'Opportunity' AND Status__c = 'Failed'
        ];
        System.assert(!skipLogs.isEmpty(), 'Expected a log entry explaining why the unconfigured job was skipped');
        System.assert(skipLogs[0].Error_Message__c.contains('AdHoc_Mask_Opportunity'),
            'Expected the log message to reference the skipped job by name: ' + skipLogs[0].Error_Message__c);
    }

    @isTest
    static void testAdHocSerialJobNameNotInCmdtDoesNotBreakCompletionTracking() {
        EnvironmentSafetyService.sandboxOverrideForTests = true;

        MaskingConfigService.JobConfig serialJob = new MaskingConfigService.JobConfig();
        serialJob.jobName = 'AdHoc_Serial_Not_In_Cmdt';
        serialJob.objectApiName = 'Contact';
        serialJob.executionMode = 'Serial';
        serialJob.sequenceOrder = 1;
        serialJob.batchSize = 200;
        serialJob.runMode = 'Full';
        serialJob.jobType = 'FIELD_MASKING';

        Test.startTest();
        MaskingJobOrchestrator.runJobs(new List<MaskingConfigService.JobConfig>{ serialJob });
        Test.stopTest();

        Contact c = [SELECT LastName FROM Contact LIMIT 1];
        System.assertNotEquals('OriginalLastName', c.LastName, 'The job itself should still run even though chain-advance is a no-op for it');

        Automation_Bypass__c settings = Automation_Bypass__c.getOrgDefaults();
        System.assertEquals(false, settings.Bypass_All_Automations__c,
            'Completion tracking must still reach 100% and re-enable automations even when the serial chain lookup finds no match in CMDT');
    }
}
