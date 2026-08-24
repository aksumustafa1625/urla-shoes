// Publishes the Partner Compliance Cockpit feature page (09) to Notion.
NotionPublisher.PublishResult r = UrlaInterviewPrepNotion.publishComplianceCockpit();
System.debug('==================== NOTION PUBLISH RESULT ====================');
System.debug('success     : ' + r.success);
System.debug('statusCode  : ' + r.statusCode);
System.debug('notionUrl   : ' + r.notionUrl);
System.debug('errorBody   : ' + r.errorBody);
System.debug('===============================================================');
