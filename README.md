# Urla Shoes - Salesforce DX Project

## Overview

Salesforce DX project for Urla Shoes. Includes an Apex solution that enriches Contact records with country data from the [Nationalize.io](https://api.nationalize.io) external API.

When a new Contact is created with a FirstName, the system automatically calls the Nationalize.io API to predict the most likely country of origin and stores the result in the `Nationalized_Country__c` field.

## Contact Nationalization Feature

### Architecture

```
Contact Insert
  -> ContactTrigger (after insert)
    -> ContactTriggerHandler.afterInsert()
      -> NationalizeService (Queueable + AllowsCallouts)
        -> HTTP GET https://api.nationalize.io/?name=<FirstName>
        -> Parse JSON -> highest probability country_id
        -> Update Contact.Nationalized_Country__c
```

### Components

| Component | Type | Location | Purpose |
|-----------|------|----------|---------|
| `ContactTrigger` | Apex Trigger | `force-app/main/default/triggers/` | Fires on Contact after insert |
| `ContactTriggerHandler` | Apex Class | `force-app/main/default/classes/handlers/` | Extends TriggerHandler, enqueues NationalizeService |
| `NationalizeService` | Apex Class | `force-app/main/default/classes/services/` | Queueable job: calls API, parses response, updates Contact |
| `NationalizeCalloutMock` | Apex Class | `force-app/main/default/classes/factories/` | HttpCalloutMock for test scenarios |
| `NationalizeServiceTest` | Apex Class | `force-app/main/default/classes/tests/` | Test class covering success, empty, error, bulk scenarios |
| `Nationalized_Country__c` | Custom Field | `force-app/main/default/objects/Contact/fields/` | Text(10) field on Contact for country code |
| `Nationalize_API` | Remote Site Setting | `force-app/main/default/remoteSiteSettings/` | Allows callout to api.nationalize.io |

### Technical Details

- **Bulk-safe**: Handler collects all Contact Ids and passes them to a single Queueable job
- **Async callout**: Uses `Queueable` with `Database.AllowsCallouts` since triggers cannot make direct HTTP callouts
- **Error handling**: Gracefully handles missing FirstName, API failures (non-200 status), empty responses, and exceptions
- **JSON parsing**: Selects the country with the highest probability from the API response

## Setup & Deployment

### Prerequisites

- Salesforce CLI (`sf` or `sfdx`)
- VS Code with Salesforce Extension Pack
- A Salesforce Developer Org or Scratch Org

### Steps

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd "Urla Shoes"
   ```

2. **Authorize your org**
   ```bash
   sf org login web --alias urla-shoes
   ```

3. **Deploy to org**
   ```bash
   sf project deploy start --target-org urla-shoes
   ```

4. **Run tests**
   ```bash
   sf apex run test --class-names NationalizeServiceTest --target-org urla-shoes --result-format human
   ```

5. **Verify**: Create a Contact with a FirstName in Salesforce. After a moment, the `Nationalized Country` field should populate with a country code.

## Running Tests

```bash
# Run all tests
sf apex run test --target-org urla-shoes --result-format human

# Run only the Nationalize tests
sf apex run test --class-names NationalizeServiceTest --target-org urla-shoes --result-format human --code-coverage
```

### Test Scenarios Covered

- **Success**: API returns country data -> field updated with highest probability country
- **Empty response**: API returns empty country array -> field stays null
- **Error**: API returns HTTP 500 -> field stays null, no exception thrown
- **No FirstName**: Contact without FirstName -> service not triggered
- **Bulk insert**: 10 contacts inserted at once -> all processed correctly
- **parseCountry unit test**: Direct method test for JSON parsing logic

## Additional Resources

- [Salesforce Extensions Documentation](https://developer.salesforce.com/tools/vscode/)
- [Salesforce CLI Setup Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_setup.meta/sfdx_setup/sfdx_setup_intro.htm)
- [Salesforce DX Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_intro.htm)
- [Nationalize.io API Documentation](https://nationalize.io/)
