/**
 * @class         PhoneMaskStrategy
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
public with sharing class PhoneMaskStrategy implements IMaskingStrategy {
    public Object maskValue(Object originalValue, String pattern, String fieldApiName) {
        if (originalValue == null) return null;
        String original = String.valueOf(originalValue);
        String masked = '';
        for (Integer i = 0; i < original.length(); i++) {
            String ch = original.substring(i, i + 1);
            if (ch.isNumeric()) {
                masked += String.valueOf(Math.mod(Math.abs(Crypto.getRandomInteger()), 10));
            } else {
                masked += ch;
            }
        }
        return masked;
    }
}
