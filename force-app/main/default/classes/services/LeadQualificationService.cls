global with sharing class LeadQualificationService {

    // ---- MCP tool girdileri (input parametreleri) ----
    global class Request {
        @InvocableVariable(
            label='Lead First Name'
            description='First name of the lead.'
            required=false)
        global String leadFirstName;

        @InvocableVariable(
            label='Lead Last Name'
            description='Last name of the lead. Required by Salesforce on the Lead record.'
            required=true)
        global String leadLastName;

        @InvocableVariable(
            label='Company Name'
            description='Company the lead belongs to. Required by Salesforce on the Lead record.'
            required=true)
        global String companyName;

        @InvocableVariable(
            label='Budget'
            description='Estimated budget of the lead. Used for scoring and stored as AnnualRevenue.'
            required=false)
        global Decimal budget;

        @InvocableVariable(
            label='Country'
            description='Country of the lead. DACH countries (Germany, Austria, Switzerland) earn bonus score points.'
            required=false)
        global String country;
    }

    // ---- MCP tool ciktilari (AI'a donen degerler) ----
    global class Response {
        @InvocableVariable(label='Lead Id' description='Id of the created Lead record.')
        global String leadId;

        @InvocableVariable(label='Rating' description='Calculated lead rating: Hot, Warm, or Cold.')
        global String rating;

        @InvocableVariable(label='Lead Score' description='Numeric lead score derived from country and budget.')
        global Decimal leadScore;

        @InvocableVariable(label='Task Created' description='True if a high-priority follow-up task was created (Hot leads only).')
        global Boolean taskCreated;

        @InvocableVariable(label='Summary' description='Human-readable summary of the lead, score, rating and recommended next step.')
        global String summary;
    }

    @InvocableMethod(
        label='Qualify and Route Lead'
        description='Creates a Lead from first name, last name, company, budget and country; scores and rates it (Hot/Warm/Cold); creates a high-priority call task for Hot leads; returns the lead id, score, rating, taskCreated flag and a summary.'
        category='Lead')
    global static List<Response> qualifyAndRoute(List<Request> requests) {
        List<Response> results = new List<Response>();

        for (Request req : requests) {
            Response res = new Response();

            // 1. Lead kaydini olustur
            Lead ld = new Lead();
            ld.LastName  = String.isBlank(req.leadLastName)  ? 'Unknown' : req.leadLastName;
            ld.FirstName = req.leadFirstName;
            ld.Company   = String.isBlank(req.companyName)   ? 'Unknown' : req.companyName;
            ld.Country   = req.country;
            if (req.budget != null) {
                ld.AnnualRevenue = req.budget;
            }

            // 2. Skor hesapla
            Decimal score = 0;

            String c = (req.country == null) ? '' : req.country.trim().toLowerCase();
            if (c == 'germany' || c == 'deutschland' || c == 'de' ||
                c == 'austria' || c == 'österreich' || c == 'osterreich' || c == 'at' ||
                c == 'switzerland' || c == 'schweiz' || c == 'ch') {
                score += 40;
            }

            Decimal b = (req.budget == null) ? 0 : req.budget;
            if (b >= 50000) {
                score += 50;
            } else if (b >= 20000) {
                score += 25;
            } else {
                score += 10;
            }

            // 3. Rating belirle
            String rating;
            if (score >= 70) {
                rating = 'Hot';
            } else if (score >= 40) {
                rating = 'Warm';
            } else {
                rating = 'Cold';
            }
            ld.Rating = rating;

            insert ld;

            res.leadId      = ld.Id;
            res.rating      = rating;
            res.leadScore   = score;
            res.taskCreated = false;

            // 4. Hot ise yuksek oncelikli task olustur
            if (rating == 'Hot') {
                Task t = new Task();
                t.Subject      = 'Call within 24h';
                t.Priority     = 'High';
                t.Status       = 'Not Started';
                t.WhoId        = ld.Id;
                t.ActivityDate = Date.today().addDays(1);
                insert t;
                res.taskCreated = true;
            }

            // 5. Summary string olustur
            String nextStep;
            if (rating == 'Hot') {
                nextStep = 'Call within 24h (task created).';
            } else if (rating == 'Warm') {
                nextStep = 'Follow up this week.';
            } else {
                nextStep = 'Add to nurture campaign.';
            }

            String fullName = ((req.leadFirstName == null ? '' : req.leadFirstName) + ' ' +
                               (req.leadLastName  == null ? '' : req.leadLastName)).trim();

            res.summary = 'Lead ' + fullName +
                          ' from ' + (req.companyName == null ? '' : req.companyName) +
                          ' (' + (req.country == null ? 'N/A' : req.country) + '). ' +
                          'Score ' + String.valueOf(score) +
                          ', rating ' + rating + '. ' +
                          'Next step: ' + nextStep;

            results.add(res);
        }

        return results;
    }
}