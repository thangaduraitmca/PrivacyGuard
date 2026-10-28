/** @class InvalidEmailMaskStrategyTest @description Tests safe random email masking. @package PrivacyGuard @namespace privacyguard @owner PrivacyGuard Engineering @changeControl PG-STRATEGY-002 */
@IsTest
private class InvalidEmailMaskStrategyTest {
    @IsTest static void masksToValidSandboxEmailFormat() {
        String v=(String)new InvalidEmailMaskStrategy().maskValue('person@example.com',null,'Email');
        System.assert(v.startsWith('sandbox.'));
        System.assert(v.endsWith('@invalid.com'));
        System.assert(Pattern.matches('^sandbox[.][a-f0-9]{12}@invalid[.]com$',v), 'Expected a syntactically valid PrivacyGuard sandbox email. Actual: '+v);
        System.assertNotEquals('person@example.com',v);
    }
    @IsTest static void nullRemainsNull() {
        System.assertEquals(null,new InvalidEmailMaskStrategy().maskValue(null,null,'Email'));
    }
}
