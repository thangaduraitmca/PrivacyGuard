trigger PGAuditMaskingFieldConfig on Masking_Field_Config__c (after insert, after update, after delete, after undelete) {
    PrivacyGuardAuditService.capture('Configuration', Trigger.isDelete ? Trigger.old : Trigger.new,
        Trigger.oldMap, Trigger.isDelete ? 'Deleted' : Trigger.isUndelete ? 'Restored' : Trigger.isInsert ? 'Created' : 'Updated');
}
