/** Explicitly clears a nullable field. Eligibility is checked at configuration and execution. */
public with sharing class NullMaskStrategy implements IMaskingStrategy {
    public Object maskValue(Object originalValue, String pattern, String fieldApiName) {
        return null;
    }
}
