/**
 * @class         MaskingConfigPromoter
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
 * 1.1.0       2026-09-16   PG-SEC-004         PrivacyGuard Engineering   Added XML namespaces and output escaping for generated metadata.
 * 1.2.0       2026-09-16   PG-PII-003         PrivacyGuard Engineering   Accepted candidates generate inactive scope records only; strategy remains an explicit admin decision.
 */
/**
 * Custom Metadata records can't be inserted with plain DML at runtime - they must be
 * deployed via the Metadata API. This class generates ready-to-deploy Custom Metadata
 * XML for every PII_Scan_Result__c row an admin has marked "Accepted", so promoting a
 * accepted candidate into an inactive masking-scope record doesn't mean hand-typing XML.
 *
 * The generated XML still needs to be deployed (e.g. saved into
 * force-app/main/default/customMetadata/ and pushed via SFDX, or applied through the
 * Metadata API/Workbench) - this class produces the file content, it doesn't deploy it.
 */
public with sharing class MaskingConfigPromoter {

    public static Map<String, String> generateMetadataXmlForAcceptedFindings() {
        Map<String, String> xmlByFileName = new Map<String, String>();

        for (PII_Scan_Result__c finding : [
            SELECT Object_API_Name__c, Field_API_Name__c
            FROM PII_Scan_Result__c
            WHERE Review_Status__c = 'Accepted' AND Already_Configured__c = false
            WITH SECURITY_ENFORCED
        ]) {
            String devName = (finding.Object_API_Name__c + '_' + finding.Field_API_Name__c)
                .replaceAll('[^a-zA-Z0-9]', '_');
            String fileName = 'Masking_Configuration.' + devName + '.md-meta.xml';

            String xml = '<?xml version="1.0" encoding="UTF-8"?>\n' +
                '<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" ' +
                    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
                    'xmlns:xsd="http://www.w3.org/2001/XMLSchema">\n' +
                '    <label>' + xmlEscape(finding.Object_API_Name__c + ' ' + finding.Field_API_Name__c) + '</label>\n' +
                '    <protected>false</protected>\n' +
                '    <values><field>Object_API_Name__c</field><value xsi:type="xsd:string">' +
                    xmlEscape(finding.Object_API_Name__c) + '</value></values>\n' +
                '    <values><field>Field_API_Name__c</field><value xsi:type="xsd:string">' +
                    xmlEscape(finding.Field_API_Name__c) + '</value></values>\n' +
                '    <values><field>Field_Type__c</field><value xsi:nil="true"/></values>\n' +
                '    <values><field>Masking_Strategy_Class__c</field><value xsi:nil="true"/></values>\n' +
                '    <values><field>Masking_Pattern__c</field><value xsi:nil="true"/></values>\n' +
                '    <values><field>Is_Active__c</field><value xsi:type="xsd:boolean">false</value></values>\n' +
                '    <values><field>Execution_Group__c</field><value xsi:type="xsd:double">1</value></values>\n' +
                '</CustomMetadata>';

            xmlByFileName.put(fileName, xml);
        }
        return xmlByFileName;
    }

    private static String xmlEscape(String value) {
        if (value == null) return '';
        return value.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
                    .replace('"', '&quot;').replace('\'', '&apos;');
    }
}
