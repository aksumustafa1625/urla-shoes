/**
 * @class       RouteWeatherAnalysis
 * @description Receives weather data for 5 route waypoints from the routeWeather LWC,
 *              passes it to the Einstein Prompt Template, and returns an AI-generated
 *              road safety assessment via Salesforce Einstein Trust Layer.
 *
 *              Flow: LWC → Apex → ConnectApi.EinsteinLLM → Prompt Template → GPT-4 Omni Mini
 *
 * @author      Mustafa Aksu
 * @project     RuhrGrid GmbH — Route & Weather Navigator Demo
 * @version     1.0
 * @date        2026-03-30
 * @see         Prompt Template: RouteWeatherAnalysis (Flex, Active)
 * @see         LWC Component: routeWeather
 */
public with sharing class RouteWeatherAnalysisService {

    /**
     * @method      analyzeRoute
     * @description Called by the routeWeather LWC. Deserializes 5-waypoint weather JSON,
     *              formats it into readable text, injects it into the Prompt Template
     *              via ConnectApi.EinsteinLLM, and returns the AI safety assessment.
     *
     * @param       waypointsJson  JSON array with fields: type, city, temp, desc, humidity, wind
     * @return      AI-generated safety assessment string. Returns error message if call fails.
     *
     * @example
     *   // LWC usage:
     *   analyzeRoute({ waypointsJson: JSON.stringify(payload) })
     *       .then(result => { this.aiAnalysis = result; });
     */
    @AuraEnabled(cacheable=false)
    public static String analyzeRoute(String waypointsJson) {
        try {

            // Step 1: Deserialize JSON string from LWC into a generic object list
            List<Object> waypoints = (List<Object>) JSON.deserializeUntyped(waypointsJson);

            // Step 2: Convert waypoint objects into a line-by-line text for the Prompt Template
            String weatherData = buildWeatherString(waypoints);

            // Step 3: Wrap the weather text in ConnectApi.WrappedValue
            // Key must exactly match the Resource API Name in the Prompt Template
            Map<String, ConnectApi.WrappedValue> inputParams = new Map<String, ConnectApi.WrappedValue>();
            ConnectApi.WrappedValue weatherValue = new ConnectApi.WrappedValue();
            weatherValue.value = weatherData;
            inputParams.put('Input:weatherData', weatherValue);

            // Step 4: Build the generation request
            // isPreview = false → live call (not draft)
            // applicationName → required by Einstein Trust Layer for audit logging
            ConnectApi.EinsteinPromptTemplateGenerationsInput promptInput =
                new ConnectApi.EinsteinPromptTemplateGenerationsInput();
            promptInput.inputParams = inputParams;
            promptInput.isPreview = false;
            promptInput.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
            promptInput.additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';

            // Step 5: Call Einstein LLM with the Prompt Template
            // Salesforce resolves the template, injects input params, routes through
            // Einstein Trust Layer (data masking, GDPR, audit), and calls GPT-4 Omni Mini
            ConnectApi.EinsteinPromptTemplateGenerationsRepresentation response =
                ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                    'RouteWeatherAnalysis',
                    promptInput
                );

            // Step 6: Return the generated text from the first response candidate
            if (response != null
                && response.generations != null
                && !response.generations.isEmpty()) {
                return response.generations[0].text;
            }

            return 'Analysis could not be generated.';

        } catch (Exception e) {
            // Log full error server-side — never expose stack traces to the UI
            System.debug('Einstein Prompt Template Error: ' + e.getMessage());
            return 'Analysis unavailable: ' + e.getMessage();
        }
    }

    /**
     * @method      buildWeatherString
     * @description Converts the waypoint list into a formatted text string
     *              for injection into the {!$Input:weatherData} merge field.
     *
     *              Output format per line:
     *              "- {TYPE} | {CITY} | {TEMP}°C | {DESC} | Humidity: {H}% | Wind: {W}"
     *
     * @param       waypoints  Deserialized list of waypoint maps from LWC
     * @return      Multi-line weather summary string ready for Prompt Template
     */
    private static String buildWeatherString(List<Object> waypoints) {
        String result = '';
        for (Object obj : waypoints) {
            Map<String, Object> wp = (Map<String, Object>) obj;
            result += '- ' + wp.get('type') + ' | ' + wp.get('city')
                   + ' | ' + wp.get('temp') + '°C | ' + wp.get('desc')
                   + ' | Humidity: ' + wp.get('humidity') + '% | Wind: ' + wp.get('wind') + '\n';
        }
        return result;
    }
}