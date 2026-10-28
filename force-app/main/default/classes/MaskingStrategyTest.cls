/**
 * @class         MaskingStrategyTest
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
private with sharing class MaskingStrategyTest {

    @isTest
    static void testEmailMaskStrategyPreservesDomain() {
        IMaskingStrategy strategy = new EmailMaskStrategy();
        Object result = strategy.maskValue('jane.doe@acme.com', null, 'Email');
        System.assert(String.valueOf(result).endsWith('@acme.com'), 'Domain should be preserved');
        System.assert(String.valueOf(result) != 'jane.doe@acme.com', 'Value should be changed');
    }

    @isTest
    static void testPhoneMaskStrategyPreservesFormat() {
        IMaskingStrategy strategy = new PhoneMaskStrategy();
        String original = '(415) 555-1234';
        Object result = strategy.maskValue(original, null, 'Phone');
        System.assertEquals(original.length(), String.valueOf(result).length(), 'Length/format should be preserved');
        System.assert(String.valueOf(result) != original, 'Digits should be changed');
    }

    @isTest
    static void testStaticValueStrategyReturnsPattern() {
        IMaskingStrategy strategy = new StaticValueMaskStrategy();
        Object result = strategy.maskValue('anything', 'MASKED', 'SomeField__c');
        System.assertEquals('MASKED', result);
    }

    @isTest
    static void testRegexReplaceStrategy() {
        IMaskingStrategy strategy = new RegexReplaceMaskStrategy();
        Object result = strategy.maskValue('123-45-6789', '[0-9]=>9', 'SSN__c');
        System.assertEquals('999-99-9999', result);
    }

    @isTest
    static void testNameMaskStrategyReturnsFromSamplePool() {
        IMaskingStrategy strategy = new NameMaskStrategy();
        Object result = strategy.maskValue('RealLastName', null, 'LastName');
        System.assertNotEquals(null, result);
        System.assertNotEquals('RealLastName', result);
    }

    @isTest
    static void testNameMaskStrategyReturnsNullForNullInput() {
        IMaskingStrategy strategy = new NameMaskStrategy();
        System.assertEquals(null, strategy.maskValue(null, null, 'LastName'));
    }

    @isTest
    static void testRandomStringMaskStrategyDefaultLength() {
        IMaskingStrategy strategy = new RandomStringMaskStrategy();
        Object result = strategy.maskValue('anything', null, 'SomeField__c');
        System.assertEquals(8, String.valueOf(result).length());
    }

    @isTest
    static void testRandomStringMaskStrategyHonorsLengthPattern() {
        IMaskingStrategy strategy = new RandomStringMaskStrategy();
        Object result = strategy.maskValue('anything', '15', 'SomeField__c');
        System.assertEquals(15, String.valueOf(result).length());
    }

    @isTest
    static void testRandomStringMaskStrategyReturnsNullForNullInput() {
        IMaskingStrategy strategy = new RandomStringMaskStrategy();
        System.assertEquals(null, strategy.maskValue(null, '10', 'SomeField__c'));
    }

    @isTest
    static void testFactoryThrowsForUnknownType() {
        Boolean threw = false;
        try {
            MaskingStrategyFactory.getStrategy('UNKNOWN_TYPE', null);
        } catch (MaskingStrategyFactory.MaskingException e) {
            threw = true;
        }
        System.assert(threw, 'Expected MaskingException for unmapped field type');
    }

    @isTest
    static void testFactoryHonorsExplicitOverride() {
        IMaskingStrategy strategy = MaskingStrategyFactory.getStrategy('ANYTHING', 'StaticValueMaskStrategy');
        System.assert(strategy instanceof StaticValueMaskStrategy);
    }
}
