/**
 * @class InvalidEmailMaskStrategy
 * @description Generates syntactically valid sandbox email values using the PrivacyGuard safe random email format.
 * @package PrivacyGuard
 * @namespace privacyguard
 * @apiVersion 66.0
 * @owner PrivacyGuard Engineering
 * @changeControl PG-CONFIG-001; peer review and automated tests required.
 * CHANGE HISTORY
 * 1.4.0 2026-09-17 PG-CONFIG-001 PrivacyGuard Engineering Initial implementation.
 * 1.6.1 2026-09-27 PG-STRATEGY-002 PrivacyGuard Engineering Generate sandbox.<token>@invalid.com values for Salesforce Email fields.
 */
public with sharing class InvalidEmailMaskStrategy implements IMaskingStrategy {
    public Object maskValue(Object originalValue, String pattern, String fieldApiName) {
        if (originalValue == null) return null;
        String seed = String.valueOf(originalValue) + ':' + String.valueOf(Crypto.getRandomInteger());
        String token = EncodingUtil.convertToHex(
            Crypto.generateDigest('SHA-256', Blob.valueOf(seed))
        ).substring(0, 12).toLowerCase();
        // Deliberately valid email syntax. The sandbox prefix makes masked data obvious.
        return 'sandbox.' + token + '@invalid.com';
    }
}
