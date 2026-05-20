// Publishes the Route & Weather feature page to Notion under the configured parent.
// Run from CLI:
//   sf apex run --target-org "Urla Shoes" --file scripts/apex/publishRouteWeatherToNotion.apex
NotionPublisher.PublishResult r = UrlaInterviewPrepNotion.publishRouteWeather();

System.debug('==================== NOTION PUBLISH RESULT ====================');
System.debug('success     : ' + r.success);
System.debug('statusCode  : ' + r.statusCode);
System.debug('notionPageId: ' + r.notionPageId);
System.debug('notionUrl   : ' + r.notionUrl);
System.debug('errorBody   : ' + r.errorBody);
System.debug('===============================================================');
