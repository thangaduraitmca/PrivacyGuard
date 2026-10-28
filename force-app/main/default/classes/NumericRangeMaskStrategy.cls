/** Random numeric masking on an inclusive, fixed decimal grid. */
public with sharing class NumericRangeMaskStrategy implements IMaskingStrategy {
    public class InvalidRangeException extends Exception {}
    public class RangeSpec {
        public Decimal minimum; public Decimal maximum; public Integer places;
        public Decimal multiplier; public Decimal firstTick; public Decimal count;
    }
    private String cachedRule;
    private RangeSpec cachedSpec;
    private static final Decimal RANDOM_SPACE=Decimal.valueOf('18446744073709551616');
    public static RangeSpec parseRule(String rule) {
        if(String.isBlank(rule)||rule.length()>255||rule.trim().endsWith('|'))
            throw invalid('Use minimum|maximum|decimal places, for example 100|999|0.');
        List<String> parts=rule.split('\\|');
        if(parts.size()!=3)throw invalid('Use minimum|maximum|decimal places, for example 10.00|99.99|2.');
        for(Integer i=0;i<parts.size();i++)parts[i]=parts[i].trim();
        if(!Pattern.matches('^-?[0-9]+(\\.[0-9]+)?$',parts[0]) || !Pattern.matches('^-?[0-9]+(\\.[0-9]+)?$',parts[1]) || !parts[2].isNumeric())
            throw invalid('Enter numeric minimum and maximum values and whole-number decimal places.');
        RangeSpec spec=new RangeSpec();
        try {spec.minimum=Decimal.valueOf(parts[0]);spec.maximum=Decimal.valueOf(parts[1]);spec.places=Integer.valueOf(parts[2]);}
        catch(Exception ex){throw invalid('Range values are invalid or too large.');}
        if(spec.places<0||spec.places>18)throw invalid('Decimal places must be between 0 and 18.');
        if(spec.minimum>spec.maximum)throw invalid('Minimum cannot be greater than maximum.');
        if(spec.minimum!=spec.minimum.setScale(spec.places)||spec.maximum!=spec.maximum.setScale(spec.places))
            throw invalid('Minimum and maximum must fit the chosen decimal places without rounding.');
        spec.multiplier=1;for(Integer i=0;i<spec.places;i++)spec.multiplier*=10;
        spec.firstTick=spec.minimum*spec.multiplier;
        spec.count=(spec.maximum-spec.minimum)*spec.multiplier+1;
        if(spec.count>RANDOM_SPACE)throw invalid('Range contains too many possible values. Reduce the range or decimal places.');
        return spec;
    }
    public static void validateRange(Schema.DescribeFieldResult field,String rule) {
        Schema.DisplayType kind=field.getType();
        if(kind!=Schema.DisplayType.DOUBLE&&kind!=Schema.DisplayType.INTEGER&&kind!=Schema.DisplayType.CURRENCY&&kind!=Schema.DisplayType.PERCENT)
            throw invalid('Numeric ranges support Number, Currency and Percent fields only.');
        if(field.isUnique())throw invalid('Random numeric ranges cannot guarantee unique values. Choose another strategy for this unique field.');
        RangeSpec spec=parseRule(rule);
        if(kind==Schema.DisplayType.INTEGER && (spec.minimum<Decimal.valueOf('-2147483648')||spec.maximum>Decimal.valueOf('2147483647'))) throw invalid('Range exceeds the bounds of an Integer field.');
        if(spec.places>field.getScale() || (kind==Schema.DisplayType.INTEGER && spec.places!=0))
            throw invalid('Decimal places exceed the scale allowed for '+field.getName()+'.');
        // The full range must fit the target; do not silently round or clamp bounds.
        SchemaValidationUtil.convertStaticMaskValue(field,String.valueOf(spec.minimum.setScale(spec.places)));
        SchemaValidationUtil.convertStaticMaskValue(field,String.valueOf(spec.maximum.setScale(spec.places)));
    }
    public Object maskValue(Object originalValue,String rule,String fieldApiName) {
        if(cachedSpec==null||cachedRule!=rule){cachedSpec=parseRule(rule);cachedRule=rule;}
        if(originalValue==null)return null;
        RangeSpec spec=cachedSpec;
        Decimal tick=0;
        if(spec.count>1) {
            // Rejection sampling avoids modulo bias; all 64 bits come from Crypto.
            Decimal accepted=(RANDOM_SPACE/spec.count).setScale(0,RoundingMode.DOWN)*spec.count;
            Decimal random;
            do {random=random64();} while(random>=accepted);
            tick=random-(random/spec.count).setScale(0,RoundingMode.DOWN)*spec.count;
        }
        return ((spec.firstTick+tick)/spec.multiplier).setScale(spec.places);
    }
    public static Object convertForField(Schema.DescribeFieldResult field,Object value) {
        if(value==null)return null;
        if(field.getType()==Schema.DisplayType.INTEGER)return Decimal.valueOf(String.valueOf(value)).intValue();
        return value;
    }
    private static Decimal random64() {
        String hex=EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0,16).toLowerCase();
        String digits='0123456789abcdef';Decimal value=0;
        for(Integer i=0;i<hex.length();i++)value=value*16+digits.indexOf(hex.substring(i,i+1));
        return value;
    }
    private static InvalidRangeException invalid(String message){return new InvalidRangeException(message);}
}
