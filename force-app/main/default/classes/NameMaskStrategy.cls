/**
 * @class         NameMaskStrategy
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
public with sharing class NameMaskStrategy implements IMaskingStrategy {
    // Small deterministic pool keeps masked data readable/testable. Swap for a bigger
    // list or an external data source by overriding Masking_Strategy_Class__c per field.
    private static final List<String> SAMPLE_NAMES = new List<String>{
        'Morgan', 'Jordan', 'Taylor', 'Casey', 'Riley',
        'Avery', 'Jamie', 'Drew', 'Cameron', 'Reese'
    };
    public Object maskValue(Object originalValue, String pattern, String fieldApiName) {
        if (originalValue == null) return null;
        Integer idx = Math.mod(Math.abs(Crypto.getRandomInteger()), SAMPLE_NAMES.size());
        return SAMPLE_NAMES[idx];
    }
}
