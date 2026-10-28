/**
 * @class         IMaskingStrategy
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
/**
 * Implement this interface to add a brand new masking strategy.
 * Register it either as the default for a Field_Type__c in MaskingStrategyFactory,
 * or reference it directly per-field via Masking_Configuration__mdt.Masking_Strategy_Class__c.
 */
public interface IMaskingStrategy {
    Object maskValue(Object originalValue, String pattern, String fieldApiName);
}
