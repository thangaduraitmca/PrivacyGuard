/**
 * @class         RegexReplaceMaskStrategy
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
public with sharing class RegexReplaceMaskStrategy implements IMaskingStrategy {
    public class InvalidRegexMaskException extends Exception {}
    private String cachedRule;
    private Pattern compiledExpression;
    private String replacement;

    // Split at the first delimiter. An empty replacement deliberately removes matches.
    private static List<String> parseRule(String rule) {
        if (String.isBlank(rule)) throw new InvalidRegexMaskException('REGEX requires a regex=>replacement rule.');
        Integer separator = rule.indexOf('=>');
        if (separator < 1) throw new InvalidRegexMaskException('REGEX requires a non-empty expression followed by =>replacement.');
        String expression = rule.substring(0, separator);
        if (String.isBlank(expression)) throw new InvalidRegexMaskException('REGEX expression cannot be blank.');
        return new List<String>{expression, rule.substring(separator + 2)};
    }

    public static void validateRule(String rule) {
        List<String> parts = parseRule(rule);
        try { Pattern.compile(parts[0]); }
        catch (Exception ex) { throw new InvalidRegexMaskException('Invalid REGEX expression. Correct its syntax before masking.'); }
    }

    public Object maskValue(Object originalValue, String rule, String fieldApiName) {
        if (compiledExpression == null || cachedRule != rule) {
            List<String> parts = parseRule(rule);
            try { compiledExpression = Pattern.compile(parts[0]); }
            catch (Exception ex) { throw new InvalidRegexMaskException('Invalid REGEX expression. Correct its syntax before masking.'); }
            cachedRule = rule;
            replacement = parts[1];
        }
        if (originalValue == null) return null;
        try {
            // A valid expression with no match intentionally leaves the value unchanged.
            return compiledExpression.matcher(String.valueOf(originalValue)).replaceAll(replacement);
        } catch (Exception ex) {
            // Do not include original values or pattern contents in error logs.
            throw new InvalidRegexMaskException('REGEX replacement failed. Review the replacement syntax and capture-group references.');
        }
    }
}
