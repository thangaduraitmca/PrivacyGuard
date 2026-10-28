/**
 * @class         SchemaValidationUtilTest
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
private with sharing class SchemaValidationUtilTest {

    @isTest
    static void testRequireValidObjectSucceedsForRealObject() {
        Schema.DescribeSObjectResult d = SchemaValidationUtil.requireValidObject('Contact');
        System.assertEquals('Contact', d.getName());
    }

    @isTest
    static void testRequireValidObjectThrowsForUnknownObject() {
        Boolean threw = false;
        try {
            SchemaValidationUtil.requireValidObject('Not_A_Real_Object__x');
        } catch (SchemaValidationUtil.InvalidSchemaReferenceException e) {
            threw = true;
        }
        System.assert(threw);
    }

    @isTest
    static void testRequireValidObjectThrowsForBlank() {
        Boolean threw = false;
        try {
            SchemaValidationUtil.requireValidObject('   ');
        } catch (SchemaValidationUtil.InvalidSchemaReferenceException e) {
            threw = true;
        }
        System.assert(threw);
    }

    @isTest
    static void testRequireValidFieldSucceedsForRealField() {
        Schema.DescribeSObjectResult d = SchemaValidationUtil.requireValidObject('Contact');
        try {
            SchemaValidationUtil.requireValidField(d, 'Email');
        } catch (Exception e) {
            System.assert(false, 'Should not have thrown for a real field: ' + e.getMessage());
        }
    }

    @isTest
    static void testRequireValidFieldThrowsForUnknownField() {
        Schema.DescribeSObjectResult d = SchemaValidationUtil.requireValidObject('Contact');
        Boolean threw = false;
        try {
            SchemaValidationUtil.requireValidField(d, 'Not_A_Real_Field__x');
        } catch (SchemaValidationUtil.InvalidSchemaReferenceException e) {
            threw = true;
        }
        System.assert(threw);
    }

    @isTest
    static void testRequireValidFieldThrowsForBlank() {
        Schema.DescribeSObjectResult d = SchemaValidationUtil.requireValidObject('Contact');
        Boolean threw = false;
        try {
            SchemaValidationUtil.requireValidField(d, '');
        } catch (SchemaValidationUtil.InvalidSchemaReferenceException e) {
            threw = true;
        }
        System.assert(threw);
    }

    @IsTest static void patch2C_FieldTypeAndStrategyContract() {
        Schema.DescribeFieldResult decimalField = Opportunity.Amount.getDescribe();
        System.assert(SchemaValidationUtil.isSupportedMaskingField(decimalField));
        SchemaValidationUtil.validateMaskingStrategy(decimalField, 'STATIC');
        Boolean rejected = false;
        try { SchemaValidationUtil.validateMaskingStrategy(decimalField, 'RANDOM_STRING'); }
        catch (SchemaValidationUtil.InvalidSchemaReferenceException e) { rejected = true; }
        System.assert(rejected, 'Numeric fields must reject non-STATIC strategies.');
        rejected = false;
        try { SchemaValidationUtil.convertStaticMaskValue(decimalField, 'ABCD'); }
        catch (SchemaValidationUtil.InvalidSchemaReferenceException e) { rejected = true; }
        System.assert(rejected, 'Invalid numeric patterns must be rejected.');
        Schema.DescribeFieldResult textField = Account.Name.getDescribe();
        SchemaValidationUtil.validateMaskingStrategy(textField, 'RANDOM_STRING');
        rejected = false;
        try { SchemaValidationUtil.validateMaskingStrategy(textField, 'PHONE'); }
        catch (SchemaValidationUtil.InvalidSchemaReferenceException e) { rejected = true; }
        System.assert(rejected, 'Text fields must reject phone-specific strategies.');
        Schema.DescribeFieldResult readonlyField = Account.Id.getDescribe();
        System.assert(!SchemaValidationUtil.isSupportedMaskingField(readonlyField));
    }
}
