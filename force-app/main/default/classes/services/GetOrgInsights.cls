/**
 * Agentforce-callable action that returns key org analytics in one call:
 * account count, reseller count, closed-won total for the last 2 months,
 * revenue this year, open pipeline, and the top customer by revenue.
 *
 * Designed to be wired to an Agentforce topic so an "Org Insights" agent can
 * answer business questions with exact, data-grounded figures.
 */
public with sharing class GetOrgInsights {

    public class Insights {
        @InvocableVariable public Integer totalAccounts;
        @InvocableVariable public Integer totalResellers;
        @InvocableVariable public Decimal closedWonLast2Months;
        @InvocableVariable public Decimal revenueThisYear;
        @InvocableVariable public Decimal openPipeline;
        @InvocableVariable public String topCustomerName;
        @InvocableVariable public Decimal topCustomerRevenue;
        @InvocableVariable public String summary;
    }

    @InvocableMethod(
        label='Get Org Insights'
        description='Returns key org metrics: total accounts, total resellers, closed-won amount in the last 2 months, revenue this year, open pipeline value, and the top customer by revenue.'
        category='Urla Shoes')
    public static List<Insights> getInsights() {
        Insights r = new Insights();

        r.totalAccounts = Database.countQuery('SELECT COUNT() FROM Account');
        try {
            r.totalResellers = Database.countQuery('SELECT COUNT() FROM Reseller__c');
        } catch (Exception e) {
            r.totalResellers = 0;
        }

        AggregateResult last2 = [
            SELECT SUM(Amount) s FROM Opportunity
            WHERE IsWon = true AND CloseDate = LAST_N_MONTHS:2
        ];
        r.closedWonLast2Months = toDecimal(last2.get('s'));

        AggregateResult yr = [
            SELECT SUM(Amount) s FROM Opportunity
            WHERE IsWon = true AND CloseDate = THIS_YEAR
        ];
        r.revenueThisYear = toDecimal(yr.get('s'));

        AggregateResult pipe = [
            SELECT SUM(Amount) s FROM Opportunity WHERE IsClosed = false
        ];
        r.openPipeline = toDecimal(pipe.get('s'));

        List<AggregateResult> top = [
            SELECT Account.Name n, SUM(Amount) s FROM Opportunity
            WHERE IsWon = true AND AccountId != null
            GROUP BY Account.Name ORDER BY SUM(Amount) DESC LIMIT 1
        ];
        if (!top.isEmpty()) {
            r.topCustomerName = (String) top[0].get('n');
            r.topCustomerRevenue = toDecimal(top[0].get('s'));
        }

        r.summary = 'Accounts: ' + r.totalAccounts + '. Resellers: ' + r.totalResellers
            + '. Closed-won last 2 months: ' + r.closedWonLast2Months
            + '. Revenue this year: ' + r.revenueThisYear
            + '. Open pipeline: ' + r.openPipeline
            + (r.topCustomerName != null
                ? ('. Top customer: ' + r.topCustomerName + ' (' + r.topCustomerRevenue + ').')
                : '.');

        return new List<Insights>{ r };
    }

    private static Decimal toDecimal(Object o) {
        return o == null ? 0 : (Decimal) o;
    }
}
