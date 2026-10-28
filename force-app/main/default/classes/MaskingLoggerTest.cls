/**
 * @class         MaskingLoggerTest
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
@isTest
private with sharing class MaskingLoggerTest {

    @isTest
    static void testLogInfoInsertsSuccessEntry() {
        Test.startTest();
        MaskingLogger.logInfo('TestJob', 'informational message');
        Test.stopTest();

        List<Masking_Log__c> logs = [SELECT Status__c, Error_Message__c FROM Masking_Log__c WHERE Job_Name__c = 'TestJob'];
        System.assertEquals(1, logs.size());
        System.assertEquals('Success', logs[0].Status__c);
    }

    @isTest
    static void testLogErrorInsertsFailedEntry() {
        Test.startTest();
        MaskingLogger.logError('TestJob', 'Contact', null, 'Email', 'boom');
        Test.stopTest();

        List<Masking_Log__c> logs = [SELECT Status__c, Field_API_Name__c FROM Masking_Log__c WHERE Job_Name__c = 'TestJob'];
        System.assertEquals(1, logs.size());
        System.assertEquals('Failed', logs[0].Status__c);
        System.assertEquals('Email', logs[0].Field_API_Name__c);
    }

    @isTest
    static void testQueueLogRequiresExplicitFlush() {
        MaskingLogger.queueLog('TestJob', 'Contact', null, 'Phone', 'queued message', 'Failed');
        System.assertEquals(0, [SELECT COUNT() FROM Masking_Log__c WHERE Job_Name__c = 'TestJob'],
            'Queued logs should not be inserted until flush() is called');

        Test.startTest();
        MaskingLogger.flush();
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Masking_Log__c WHERE Job_Name__c = 'TestJob']);
    }

    @isTest
    static void testFlushWithNothingQueuedIsANoOp() {
        Test.startTest();
        MaskingLogger.flush();
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Masking_Log__c]);
    }
}
