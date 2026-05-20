// Publishes all 8 features to Notion under the configured parent page.
// Run from CLI:
//   sf apex run --target-org "Urla Shoes" --file scripts/apex/publishAllToNotion.apex
List<NotionPublisher.PublishResult> results = UrlaInterviewPrepNotion.publishAll();

System.debug('==================== NOTION PUBLISH SUMMARY ====================');
Integer i = 1;
for (NotionPublisher.PublishResult r : results) {
    String prefix = i < 10 ? '0' + i : '' + i;
    System.debug(prefix + '. ' + (r.success ? '✓ ' : '✗ ') + r.statusCode + ' → ' + (r.success ? r.notionUrl : r.errorBody));
    i++;
}
System.debug('================================================================');
