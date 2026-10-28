/**
 * @class         EmailMaskStrategy
 * @description   Apex class for the PrivacyGuard managed package. See the implementation comments below for functional and security design details.
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
public with sharing class EmailMaskStrategy implements IMaskingStrategy {
    public Object maskValue(Object originalValue, String pattern, String fieldApiName) {
        if (originalValue == null) return null;
        String original = String.valueOf(originalValue);
        Integer atIndex = original.indexOf('@');
        String domain = atIndex > -1 ? original.substring(atIndex) : '@example.com';
        Integer rnd = Math.abs(Crypto.getRandomInteger());
        String suffix = String.valueOf(rnd);
        suffix = suffix.substring(0, Math.min(8, suffix.length()));
        return 'user' + suffix + domain;
    }
}
