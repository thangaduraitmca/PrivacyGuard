/**
 * @class         MaskingScheduler
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
 * Optional: schedule a masking run, e.g. nightly refresh of a sandbox.
 *   System.schedule('Nightly Sandbox Mask', '0 0 2 * * ?', new MaskingScheduler());
 */
public with sharing class MaskingScheduler implements Schedulable {
    public void execute(SchedulableContext ctx) {
        MaskingFrameworkService.executeMaskingRun();
    }
}
