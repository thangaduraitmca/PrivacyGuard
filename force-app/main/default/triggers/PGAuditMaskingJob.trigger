trigger PGAuditMaskingJob on Masking_Job__c (after insert, after update, after delete, after undelete) {
    PrivacyGuardAuditService.capture('Jobs', Trigger.isDelete ? Trigger.old : Trigger.new,
        Trigger.oldMap, Trigger.isDelete ? 'Deleted' : Trigger.isUndelete ? 'Restored' : Trigger.isInsert ? 'Created' : 'Updated');
}
