/**
 * @class         MaskingStrategyFactory
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
 * NAMESPACE NOTE: the six built-in strategies are resolved via compile-time `.class`
 * literals, NOT Type.forName() string lookups. Type.forName(String) is a runtime
 * string-based lookup whose resolution across namespace boundaries isn't something
 * that can be safely assumed without testing against a live namespaced org - using
 * `.class` literals instead lets the Apex compiler bind these references correctly
 * regardless of namespace, with zero runtime ambiguity. Type.forName() is still used,
 * deliberately, for the one case where it's actually necessary: an admin's own custom
 * strategy class name, typed into Masking_Strategy_Class__c, which by definition isn't
 * known at compile time and normally lives in the subscriber org's own (unnamespaced)
 * code, not this package.
 */
public with sharing class MaskingStrategyFactory {

    // Compile-time bound - resolves correctly regardless of this package's namespace.
    private static final Map<String, Type> DEFAULT_STRATEGY_BY_FIELD_TYPE = new Map<String, Type>{
        'EMAIL' => EmailMaskStrategy.class,
        'EMAIL_INVALID' => InvalidEmailMaskStrategy.class,
        'PHONE' => PhoneMaskStrategy.class,
        'NAME' => NameMaskStrategy.class,
        'LIST' => ListMaskStrategy.class,
        'RANDOM_STRING' => RandomStringMaskStrategy.class,
        'STATIC' => StaticValueMaskStrategy.class,
        'NUMBER_RANGE' => NumericRangeMaskStrategy.class,
        'NULL' => NullMaskStrategy.class,
        'REGEX' => RegexReplaceMaskStrategy.class
    };

    public static IMaskingStrategy getStrategy(String fieldType, String explicitStrategyClass) {
        Type strategyType;
        String resolvedNameForErrors;

        if (String.isNotBlank(explicitStrategyClass)) {
            // Genuinely dynamic case: an admin-supplied class name, resolved at runtime.
            resolvedNameForErrors = explicitStrategyClass;
            strategyType = Type.forName(explicitStrategyClass);
        } else {
            String key = String.isBlank(fieldType) ? '' : fieldType.toUpperCase();
            resolvedNameForErrors = fieldType;
            strategyType = DEFAULT_STRATEGY_BY_FIELD_TYPE.get(key);
        }

        if (strategyType == null) {
            throw new MaskingException('No masking strategy found for: ' + resolvedNameForErrors +
                '. Set Masking_Strategy_Class__c explicitly, or use a supported Field Type (' +
                String.join(new List<String>(DEFAULT_STRATEGY_BY_FIELD_TYPE.keySet()), ', ') + ').');
        }

        Object instance = strategyType.newInstance();
        if (!(instance instanceof IMaskingStrategy)) {
            throw new MaskingException(resolvedNameForErrors + ' does not implement IMaskingStrategy.');
        }
        return (IMaskingStrategy) instance;
    }

    public class MaskingException extends Exception {}
}
