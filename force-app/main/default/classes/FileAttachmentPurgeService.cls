/** Deprecated object-wide purge; all invocations fail closed. */
public with sharing class FileAttachmentPurgeService {

    public class ObjectPurgeDisabledException extends Exception {}
    public static void assertObjectPurgeEnabled() {
        throw new ObjectPurgeDisabledException('Object-wide purge is disabled. Use All files to review and explicitly select accessible items for deletion.');
    }
    public static void purgeForObjects(List<String> objectApiNames, Boolean deleteAttachments, Boolean deleteFiles) {
        EnvironmentSafetyService.assertExecutionAllowed();
        PrivacyGuardSecurityService.requirePurgePermission();
        assertObjectPurgeEnabled();
    }
}
