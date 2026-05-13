/**
 * Returns API keys stored in the API_Config__c hierarchical custom setting.
 * Both the RouteMapPage Visualforce page (server-rendered) and the
 * routeWeather LWC (via @AuraEnabled) read from here so no key string
 * ever lives in source control.
 *
 * Setup after deploying this project:
 *   1. Setup → Custom Settings → API Config → Manage
 *   2. New (Default Organization Level Value)
 *   3. Paste the Google Maps API key into "Google Maps API Key"
 *   4. Paste the OpenWeather API key into "OpenWeather API Key"
 *   5. Save
 *
 * If a key is missing, callers receive an empty string and degrade
 * gracefully — the map shows an inline error; weather fetches fail
 * with a clear message in the LWC.
 */
public with sharing class ApiKeyService {

    /** VF binding: <apex:page controller="ApiKeyService"> → {!mapsApiKey}. */
    public String mapsApiKey {
        get { return readKey('Google_Maps_Api_Key__c'); }
    }

    /** LWC binding: import getOpenWeatherApiKey from '@salesforce/apex/...'. */
    @AuraEnabled(cacheable=true)
    public static String getOpenWeatherApiKey() {
        return readKey('OpenWeather_Api_Key__c');
    }

    /** Optional LWC binding for the Maps key, mirrors the VF property. */
    @AuraEnabled(cacheable=true)
    public static String getGoogleMapsApiKey() {
        return readKey('Google_Maps_Api_Key__c');
    }

    private static String readKey(String fieldName) {
        API_Config__c config = API_Config__c.getOrgDefaults();
        if (config == null) {
            return '';
        }
        Object value = config.get(fieldName);
        return (value == null) ? '' : String.valueOf(value);
    }
}
