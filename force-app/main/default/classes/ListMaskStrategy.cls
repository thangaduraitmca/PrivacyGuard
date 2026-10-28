/** Random replacement from an administrator-supplied pipe-separated list. */
public with sharing class ListMaskStrategy implements IMaskingStrategy {
    public class InvalidListException extends Exception {}
    private String cachedRule;
    private List<String> cachedValues;
    public static List<String> parseValues(String rule) {
        if(String.isBlank(rule)) throw new InvalidListException('Enter replacement values separated by |, for example Morgan|Jordan|Taylor.');
        if(rule.length()>255) throw new InvalidListException('Replacement list must be 255 characters or fewer.');
        if(rule.trim().endsWith('|')) throw new InvalidListException('Replacement list cannot contain empty entries.');
        List<String> values=new List<String>();
        Set<String> seen=new Set<String>();
        for(String entry:rule.split('\\|')) {
            String value=entry.trim();
            if(String.isBlank(value)) throw new InvalidListException('Replacement list cannot contain empty entries.');
            if(!seen.contains(value)){values.add(value);seen.add(value);}
        }
        if(values.isEmpty()) throw new InvalidListException('Enter at least one replacement value.');
        return values;
    }
    public static void validateValues(Schema.DescribeFieldResult target,String rule) {
        Schema.DisplayType kind=target.getType();
        if(kind!=Schema.DisplayType.STRING && kind!=Schema.DisplayType.TEXTAREA &&
           kind!=Schema.DisplayType.EMAIL && kind!=Schema.DisplayType.PHONE && kind!=Schema.DisplayType.URL)
            throw new InvalidListException('Replacement lists are supported for text, email, phone and URL fields only.');
        if(target.isUnique()) throw new InvalidListException('Replacement lists cannot be used on unique fields because values can repeat.');
        for(String value:parseValues(rule)) {
            if(value.length()>target.getLength()) throw new InvalidListException('A replacement value exceeds the maximum length for '+target.getName()+'.');
        }
    }
    public Object maskValue(Object originalValue,String pattern,String fieldApiName) {
        if(cachedValues==null||cachedRule!=pattern){cachedValues=parseValues(pattern);cachedRule=pattern;}
        if(originalValue==null)return null;
        Integer index=Math.mod(Crypto.getRandomInteger(),cachedValues.size());
        if(index<0)index=-index;
        return cachedValues[index];
    }
}
