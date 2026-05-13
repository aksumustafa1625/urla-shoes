@isTest
private class ApiKeyServiceTest {

    @isTest
    static void returnsConfiguredKeys() {
        API_Config__c config = new API_Config__c(
            SetupOwnerId           = UserInfo.getOrganizationId(),
            Google_Maps_Api_Key__c = 'test-maps-key-XYZ',
            OpenWeather_Api_Key__c = 'test-weather-key-ABC'
        );
        insert config;

        Test.startTest();
        ApiKeyService instance = new ApiKeyService();

        System.assertEquals(
            'test-maps-key-XYZ',
            instance.mapsApiKey,
            'mapsApiKey should return the configured value'
        );
        System.assertEquals(
            'test-weather-key-ABC',
            ApiKeyService.getOpenWeatherApiKey(),
            'getOpenWeatherApiKey should return the configured value'
        );
        System.assertEquals(
            'test-maps-key-XYZ',
            ApiKeyService.getGoogleMapsApiKey(),
            'getGoogleMapsApiKey should return the configured value'
        );
        Test.stopTest();
    }

    @isTest
    static void returnsEmptyWhenNotConfigured() {
        Test.startTest();
        ApiKeyService instance = new ApiKeyService();

        System.assertEquals('', instance.mapsApiKey,
            'mapsApiKey should be empty when the custom setting has no record');
        System.assertEquals('', ApiKeyService.getOpenWeatherApiKey(),
            'OpenWeather key should be empty when the custom setting has no record');
        System.assertEquals('', ApiKeyService.getGoogleMapsApiKey(),
            'Google Maps key should be empty when the custom setting has no record');
        Test.stopTest();
    }
}
