global with sharing class OnboardReseller {

    global class Request {
        @InvocableVariable(
            label='Reseller Name'
            description='Name of the reseller (Account) to onboard. Created if it does not already exist.'
            required=true)
        global String resellerName;

        @InvocableVariable(
            label='Deal Amount'
            description='Value of the initial deal in currency. Used to automatically calculate the reseller tier (Silver/Gold/Platinum).'
            required=true)
        global Decimal dealAmount;
    }

    global class Result {
        @InvocableVariable(label='Account Id' description='Id of the reseller Account.')
        global Id accountId;

        @InvocableVariable(label='Contact Id' description='Id of the created primary Contact.')
        global Id contactId;

        @InvocableVariable(label='Opportunity Id' description='Id of the created Opportunity.')
        global Id opportunityId;

        @InvocableVariable(label='Quote Id' description='Id of the created Quote, if Quotes are enabled.')
        global Id quoteId;

        @InvocableVariable(label='Tier' description='Calculated reseller tier: Silver, Gold, or Platinum.')
        global String tier;

        @InvocableVariable(label='Commission Rate' description='Commission rate applied based on tier.')
        global String commissionRate;

        @InvocableVariable(label='Summary' description='Human-readable summary and recommended next step.')
        global String summary;
    }

    @InvocableMethod(
        label='Onboard Reseller'
        description='Onboards a new reseller end-to-end. Creates the Account (if needed), automatically calculates the reseller tier from the deal amount (Platinum >= 50000, Gold >= 20000, otherwise Silver), then creates a Contact, an Opportunity, and a Quote. Returns the tier, commission rate, created record Ids, and a recommended next action.')
    global static List<Result> onboard(List<Request> requests) {
        List<Result> results = new List<Result>();

        for (Request req : requests) {
            Result res = new Result();

            String tier;
            String commission;
            String oppStage;
            if (req.dealAmount >= 50000) {
                tier = 'Platinum';   commission = '15%'; oppStage = 'Negotiation/Review';
            } else if (req.dealAmount >= 20000) {
                tier = 'Gold';       commission = '10%'; oppStage = 'Proposal/Price Quote';
            } else {
                tier = 'Silver';     commission = '5%';  oppStage = 'Prospecting';
            }
            res.tier = tier;
            res.commissionRate = commission;

            Account acc;
            List<Account> existing = [
                SELECT Id, Name FROM Account WHERE Name = :req.resellerName LIMIT 1
            ];
            if (!existing.isEmpty()) {
                acc = existing[0];
            } else {
                acc = new Account(Name = req.resellerName);
                insert acc;
            }
            res.accountId = acc.Id;

            Contact con = new Contact(
                LastName = req.resellerName + ' Primary Contact',
                AccountId = acc.Id
            );
            insert con;
            res.contactId = con.Id;

            Opportunity opp = new Opportunity(
                Name = req.resellerName + ' - ' + tier + ' Onboarding Deal',
                AccountId = acc.Id,
                StageName = oppStage,
                CloseDate = Date.today().addDays(30),
                Amount = req.dealAmount
            );
            insert opp;
            res.opportunityId = opp.Id;

            try {
                if (Quote.SObjectType.getDescribe().isCreateable()) {
                    Quote q = new Quote(
                        Name = req.resellerName + ' - ' + tier + ' Quote',
                        OpportunityId = opp.Id
                    );
                    insert q;
                    res.quoteId = q.Id;
                }
            } catch (Exception e) {
                res.quoteId = null;
            }

            String nextStep;
            if (tier == 'Platinum') {
                nextStep = 'Assign a senior account manager and schedule an executive kickoff call.';
            } else if (tier == 'Gold') {
                nextStep = 'Send the partner welcome kit and schedule a product training session.';
            } else {
                nextStep = 'Add to the standard nurture sequence and review again next quarter.';
            }

            res.summary =
                req.resellerName + ' onboarded as a ' + tier + ' reseller '
                + '(deal ' + String.valueOf(req.dealAmount) + ', commission ' + commission + '). '
                + 'Created Contact, Opportunity'
                + (res.quoteId != null ? ', and Quote. ' : ' (Quote skipped - not enabled). ')
                + 'Recommended next step: ' + nextStep;

            results.add(res);
        }

        return results;
    }
}