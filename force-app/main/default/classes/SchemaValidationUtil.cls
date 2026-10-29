/**
 * @class         SchemaValidationUtil
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
 * Guards every place this framework builds dynamic SOQL from a configured or
 * user-supplied string (object/field API names from Custom Metadata, or typed
 * directly into the Attachment/File Purge LWC). Every object and field name is
 * checked against the real org schema via describe calls BEFORE it's concatenated
 * into a query string - an attacker (or a fat-fingered admin) can't smuggle SOQL
 * syntax through these values, because only strings that exactly match a real,
 * describable object/field name are ever allowed through. This is the standard
 * mitigation for SOQL injection when object/field names must be dynamic.
 */
public with sharing class SchemaValidationUtil {

    public class InvalidSchemaReferenceException extends Exception {}

    /** Returns the describe result for objectApiName, or throws if it isn't a real, describable SObject. */
    public static Schema.DescribeSObjectResult requireValidObject(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            throw new InvalidSchemaReferenceException('Object API name cannot be blank.');
        }
        Schema.SObjectType sobjType = Schema.getGlobalDescribe().get(objectApiName.trim());
        if (sobjType == null) {
            throw new InvalidSchemaReferenceException('Unknown object API name: ' + objectApiName);
        }
        return sobjType.getDescribe();
    }

    /** Throws unless fieldApiName is a real field on the already-validated object describe. */
    public static void requireValidField(Schema.DescribeSObjectResult objDescribe, String fieldApiName) {
        if (String.isBlank(fieldApiName)) {
            throw new InvalidSchemaReferenceException('Field API name cannot be blank on ' + objDescribe.getName() + '.');
        }
        Map<String, Schema.SObjectField> fieldsMap = PrivacyGuardSchema.fields(objDescribe);
        if (!fieldsMap.containsKey(fieldApiName.trim().toLowerCase())) {
            throw new InvalidSchemaReferenceException('Unknown field API name: ' + fieldApiName + ' on ' + objDescribe.getName());
        }
    }
    /** Shared eligibility contract for configuration and execution. */
    public static Boolean isSupportedMaskingField(Schema.DescribeFieldResult d) {
        if (!d.isUpdateable() || d.isCalculated() || d.isAutoNumber()) return false;
        Schema.DisplayType t = d.getType();
        return t == Schema.DisplayType.STRING || t == Schema.DisplayType.TEXTAREA ||
            t == Schema.DisplayType.EMAIL || t == Schema.DisplayType.PHONE ||
            t == Schema.DisplayType.URL || t == Schema.DisplayType.DOUBLE ||
            t == Schema.DisplayType.INTEGER || t == Schema.DisplayType.CURRENCY ||
            t == Schema.DisplayType.PERCENT || t == Schema.DisplayType.DATE ||
            t == Schema.DisplayType.DATETIME || t == Schema.DisplayType.BOOLEAN;
    }

    /** Reject strategies the standard masking engine cannot safely apply to this field. */
    public static void validateMaskingStrategy(Schema.DescribeFieldResult d, String strategy) {
        if (!isSupportedMaskingField(d))
            throw new InvalidSchemaReferenceException('Unsupported masking field type: ' + d.getName() + ' (' + d.getType() + ').');
        if (String.isBlank(strategy)) return; // Inactive discovery draft.
        String s = strategy.trim().toUpperCase();
        if(s=='NUMBER_RANGE') {
            Schema.DisplayType numericType=d.getType();
            if(numericType!=Schema.DisplayType.DOUBLE&&numericType!=Schema.DisplayType.INTEGER&&numericType!=Schema.DisplayType.CURRENCY&&numericType!=Schema.DisplayType.PERCENT) throw new InvalidSchemaReferenceException('Numeric ranges support Number, Currency and Percent fields only.');
            return;
        }
        if (s == 'NULL') {
            if (!d.isNillable()) throw new InvalidSchemaReferenceException('Cannot set ' + d.getName() + ' to NULL because it is a required field. Choose another masking strategy.');
            return;
        }
        Schema.DisplayType t = d.getType();
        Set<String> allowed;
        if (t == Schema.DisplayType.DOUBLE || t == Schema.DisplayType.INTEGER ||
            t == Schema.DisplayType.CURRENCY || t == Schema.DisplayType.PERCENT ||
            t == Schema.DisplayType.DATE || t == Schema.DisplayType.DATETIME ||
            t == Schema.DisplayType.BOOLEAN) allowed = new Set<String>{'STATIC'};
        else if (t == Schema.DisplayType.EMAIL) allowed = new Set<String>{'EMAIL_INVALID','EMAIL','STATIC','REGEX','LIST'};
        else if (t == Schema.DisplayType.PHONE) allowed = new Set<String>{'PHONE','STATIC','REGEX','LIST'};
        else allowed = new Set<String>{'NAME','RANDOM_STRING','STATIC','REGEX','LIST'};
        if (!allowed.contains(s))
            throw new InvalidSchemaReferenceException('Strategy ' + strategy + ' is not supported for ' + d.getName() + ' (' + t + ').');
    }

    /** Fail closed before a batch query starts. Custom strategies remain text-only until typed contracts exist. */
    public static void validateMaskingTarget(Schema.DescribeSObjectResult obj, MaskingConfigService.FieldConfig cfg) {
        requireValidField(obj, cfg.fieldApiName);
        cfg.fieldApiName=PrivacyGuardSchema.name(obj,cfg.fieldApiName);
        Schema.DescribeFieldResult d = PrivacyGuardSchema.field(obj,cfg.fieldApiName).getDescribe();
        Schema.DisplayType t = d.getType();
        String strategy = String.isBlank(cfg.fieldType) ? '' : cfg.fieldType.trim().toUpperCase();
        Boolean textType = t == Schema.DisplayType.STRING || t == Schema.DisplayType.TEXTAREA ||
            t == Schema.DisplayType.EMAIL || t == Schema.DisplayType.PHONE || t == Schema.DisplayType.URL;
        Boolean nullStrategy = strategy == 'NULL' && String.isBlank(cfg.strategyClass);
        Boolean numericRange = strategy == 'NUMBER_RANGE';
        if(numericRange) {
            if(String.isNotBlank(cfg.strategyClass) && !cfg.strategyClass.equalsIgnoreCase('NumericRangeMaskStrategy') && !cfg.strategyClass.equalsIgnoreCase('privacyguard.NumericRangeMaskStrategy')) throw new InvalidSchemaReferenceException('NUMBER_RANGE must use the built-in numeric range strategy.');
            NumericRangeMaskStrategy.validateRange(d,cfg.maskingPattern);
        }
        if (strategy == 'NULL' && !String.isBlank(cfg.strategyClass)) throw new InvalidSchemaReferenceException('Clear value (NULL) must use the built-in masking strategy.');
        Boolean typedStatic = strategy == 'STATIC' && (String.isBlank(cfg.strategyClass) || cfg.strategyClass.trim().equalsIgnoreCase('StaticValueMaskStrategy') || cfg.strategyClass.trim().equalsIgnoreCase('privacyguard.StaticValueMaskStrategy'));
        Boolean typedSupported = t == Schema.DisplayType.DOUBLE || t == Schema.DisplayType.INTEGER ||
            t == Schema.DisplayType.CURRENCY || t == Schema.DisplayType.PERCENT ||
            t == Schema.DisplayType.DATE || t == Schema.DisplayType.DATETIME || t == Schema.DisplayType.BOOLEAN;
        validateMaskingStrategy(d, strategy);
        if (strategy == 'REGEX' && String.isBlank(cfg.strategyClass)) RegexReplaceMaskStrategy.validateRule(cfg.maskingPattern);
        if (strategy == 'LIST') {
            if (String.isNotBlank(cfg.strategyClass) && !cfg.strategyClass.equalsIgnoreCase('ListMaskStrategy') && !cfg.strategyClass.equalsIgnoreCase('privacyguard.ListMaskStrategy')) throw new InvalidSchemaReferenceException('LIST must use the built-in list strategy.');
            ListMaskStrategy.validateValues(d,cfg.maskingPattern);
        }
        if (!isSupportedMaskingField(d) ||
            !(textType || ((typedStatic || nullStrategy || numericRange) && typedSupported))) {
            throw new InvalidSchemaReferenceException('Unsupported masking target or strategy: ' + obj.getName() + '.' + cfg.fieldApiName + ' (' + String.valueOf(t) + ').');
        }
        if (typedStatic) {
            Object value = convertStaticMaskValue(d, cfg.maskingPattern);
            if (value == null && !d.isNillable()) throw new InvalidSchemaReferenceException('Required field cannot be masked to null: ' + cfg.fieldApiName);
        }
    }

    /** Convert STATIC configuration to a value matching the actual Salesforce field type. */
    public static Object convertStaticMaskValue(Schema.DescribeFieldResult d, String pattern) {
        Schema.DisplayType t = d.getType();
        if (pattern == null) return null;
        try {
            if (t == Schema.DisplayType.DATE) return Date.valueOf(pattern);
            if (t == Schema.DisplayType.DATETIME) return Datetime.valueOf(pattern);
            if (t == Schema.DisplayType.BOOLEAN) {
                if (pattern != 'true' && pattern != 'false') throw new InvalidSchemaReferenceException('Checkbox requires true or false.');
                return pattern == 'true';
            }
            if (t == Schema.DisplayType.DOUBLE || t == Schema.DisplayType.INTEGER ||
                t == Schema.DisplayType.CURRENCY || t == Schema.DisplayType.PERCENT) {
                Decimal n = Decimal.valueOf(pattern);
                if (t == Schema.DisplayType.INTEGER) {
                    if (n != n.setScale(0)) throw new InvalidSchemaReferenceException('Integer requires a whole number.');
                    if (n < Decimal.valueOf('-2147483648') || n > Decimal.valueOf('2147483647'))
                        throw new InvalidSchemaReferenceException('Numeric value exceeds Integer bounds.');
                    // Integer fields use signed 32-bit bounds; decimal precision metadata
                    // is not a reliable capacity limit for standard integer fields.
                    return n;
                }
                Integer scale = d.getScale();
                Integer precision = d.getPrecision();
                String digits = String.valueOf(n.abs());
                List<String> parts = digits.split('\\.');
                Integer fractional = parts.size() > 1 ? parts[1].length() : 0;
                Integer whole = parts[0].replaceFirst('^0+', '').length();
                if (fractional > scale || whole > precision - scale) throw new InvalidSchemaReferenceException('Numeric value exceeds field precision or scale.');
                return n;
            }
            if (pattern.length() > d.getLength()) throw new InvalidSchemaReferenceException('Static masking value exceeds field length.');
            return pattern;
        } catch (Exception ex) {
            throw new InvalidSchemaReferenceException('Invalid STATIC masking value for ' + d.getName() + ': ' + ex.getMessage());
        }
    }

}
