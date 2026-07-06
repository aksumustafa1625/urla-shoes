@isTest
private class EmailUtilsTest {

    @isTest
    static void normalizeEmailTrimsAndLowercases() {
        System.assertEquals('partner@bursa.com', EmailUtils.normalizeEmail('  Partner@Bursa.COM '),
            'email trimmed and lowercased');
    }

    @isTest
    static void normalizeEmailReturnsNullForBlank() {
        System.assertEquals(null, EmailUtils.normalizeEmail(null), 'null input -> null');
        System.assertEquals(null, EmailUtils.normalizeEmail('   '), 'blank input -> null');
    }

    @isTest
    static void normalizeEmailReturnsNullWithoutAtSign() {
        System.assertEquals(null, EmailUtils.normalizeEmail('not-an-email'), 'missing @ -> null');
    }

    @isTest
    static void extractDomainReturnsDomainPart() {
        System.assertEquals('bursa.com', EmailUtils.extractDomain('partner@bursa.com'),
            'domain extracted after @');
    }

    @isTest
    static void extractDomainReturnsNullForBlank() {
        System.assertEquals(null, EmailUtils.extractDomain(null), 'null input -> null');
        System.assertEquals(null, EmailUtils.extractDomain('   '), 'blank input -> null');
    }

    @isTest
    static void extractDomainReturnsNullWithoutAtSign() {
        System.assertEquals(null, EmailUtils.extractDomain('bursa.com'), 'missing @ -> null');
    }

    @isTest
    static void extractDomainReturnsNullWhenDomainMissing() {
        System.assertEquals(null, EmailUtils.extractDomain('partner@'), 'empty domain part -> null');
    }
}
