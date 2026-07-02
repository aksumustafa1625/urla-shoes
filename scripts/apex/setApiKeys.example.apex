/*
 * setApiKeys.example.apex  —  COMMITTED TEMPLATE (no real keys here)
 * ------------------------------------------------------------------
 * Populates the API_Config__c hierarchical Custom Setting so the
 * RouteMapPage (Google Maps), routeWeather and essenWeather (OpenWeather)
 * components can read their keys at runtime via ApiKeyService.
 *
 * HOW TO USE (local, one-time):
 *   1. Copy this file to  scripts/apex/setApiKeys.apex   (that name is
 *      gitignored, so your real keys never get committed).
 *   2. Paste your real keys into the two placeholders below.
 *   3. Run it against the org:
 *        sf apex run --file scripts/apex/setApiKeys.apex --target-org "Urla Shoes"
 *
 * The keys live only in the org's Custom Setting DATA — never in source control.
 */

API_Config__c cfg = API_Config__c.getOrgDefaults();
if (cfg == null)      { cfg = new API_Config__c(); }
if (cfg.Id == null)   { cfg.SetupOwnerId = UserInfo.getOrganizationId(); }

cfg.Google_Maps_Api_Key__c = 'PASTE_GOOGLE_MAPS_KEY_HERE';
cfg.OpenWeather_Api_Key__c = 'PASTE_OPENWEATHER_KEY_HERE';

upsert cfg;

System.debug('API_Config__c updated — ' +
    'maps='    + (String.isBlank(cfg.Google_Maps_Api_Key__c) ? 'EMPTY' : 'set') + ', ' +
    'weather=' + (String.isBlank(cfg.OpenWeather_Api_Key__c) ? 'EMPTY' : 'set'));
