// Publishes the remaining 7 features to Notion (Route & Weather already published).
// Run from CLI:
//   sf apex run --target-org "Urla Shoes" --file scripts/apex/publishRemainingToNotion.apex
List<NotionPublisher.PublishResult> results = new List<NotionPublisher.PublishResult>();
results.add(UrlaInterviewPrepNotion.publishNationalization());
results.add(UrlaInterviewPrepNotion.publishLoanCreation());
results.add(UrlaInterviewPrepNotion.publishResellerMatching());
results.add(UrlaInterviewPrepNotion.publishLeadQueue());
results.add(UrlaInterviewPrepNotion.publishTierBadge());
results.add(UrlaInterviewPrepNotion.publishTaskAggregation());
results.add(UrlaInterviewPrepNotion.publishFileHub());

System.debug('==================== NOTION PUBLISH SUMMARY ====================');
Integer i = 2; // Route & Weather was 01, these start at 02
for (NotionPublisher.PublishResult r : results) {
    System.debug('0' + i + '. ' + (r.success ? '✓ ' : '✗ ') + r.statusCode + ' → ' + (r.success ? r.notionUrl : r.errorBody));
    i++;
}
System.debug('================================================================');
