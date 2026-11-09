/** Restrict audit mutation and suppress raw failed-operation text at persistence. */
trigger PGProtectMaskingLog on Masking_Log__c (before insert, before update, before delete) {
    if (Trigger.isInsert) {
        for (Masking_Log__c entry : Trigger.new) {
            if (entry.Status__c == 'Failed') {
                entry.Error_Message__c = 'Operation failed. Review the operation status and affected record identifiers.';
                entry.Technical_Details__c = null;
                entry.Admin_Message__c = 'Review configuration, permissions and Salesforce automation before retrying.';
                entry.Change_Details__c = null;
            }
        }
    } else {
        for (Masking_Log__c entry : Trigger.isDelete ? Trigger.old : Trigger.new) {
            entry.addError('PrivacyGuard audit entries cannot be edited or deleted.');
        }
    }
}
