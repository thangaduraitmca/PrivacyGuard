/** Functional tests use the same packaged administrator permissions as a real operator. */
@IsTest
public class PrivacyGuardPackageTestAccess {
    public static void grantAdmin() {
        String prefix=PrivacyGuardSchema.namespacePrefix();
        String ns=prefix==''?null:prefix.substring(0,prefix.length()-2);
        PermissionSet admin=[SELECT Id FROM PermissionSet WHERE Name='PrivacyGuard_Admin' AND NamespacePrefix=:ns LIMIT 1];
        Id currentUser=UserInfo.getUserId();
        if([SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId=:currentUser AND PermissionSetId=:admin.Id]>0)return;
        // runAs is test-only and permits setup DML alongside a test's existing data setup.
        System.runAs(new User(Id=currentUser)) {
            insert new PermissionSetAssignment(AssigneeId=currentUser,PermissionSetId=admin.Id);
        }
    }
}
