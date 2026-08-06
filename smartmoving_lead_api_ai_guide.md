title: "SmartMoving Lead API Integration Guide"
document_type: "API integration reference"
audience:

"AI coding assistants"
"Developers"
"Integration engineers"
source_author: "Matt Honeycutt"
source_date: "2026-06-03"
api_version: "v2"

SmartMoving Lead API Integration Guide
Purpose
Use this API to submit leads from:

A website form
An existing HTML form
A third-party lead source

After a successful submission, SmartMoving creates a new lead automatically.
API Endpoint
Send an HTTP POST request to:
texthttps://api.smartmoving.com/api/leads/from-provider/v2?providerKey={provider_key}
To force submissions from a form into a specific branch, append the branch ID:
texthttps://api.smartmoving.com/api/leads/from-provider/v2?providerKey={provider_key}&branchId={branchId}
Replace:

{provider_key} with the company's SmartMoving provider key.
{branchId} with the SmartMoving branch ID.

Required HTTP Header
httpContent-Type: application/json
Finding the Provider Key
In SmartMoving, navigate to:
textSettings > Sales > Lead Providers > Your Website > View Instructions
A popup displays the provider key for the company.
Request Format

Submit one JSON object in the request body.
Every submitted property must be at the root level of the JSON object.
Do not nest customer, origin, destination, UTM, or custom fields inside child objects.
Only the customer name is required.
Custom fields are allowed and are added to the lead's notes.

Critical Validation Rules
Customer Name
Provide exactly one of these two name formats:

firstName and lastName
fullName

Do not submit both formats in the same request.
Valid:
json{
"firstName": "John",
"lastName": "Smith"
}
Valid:
json{
"fullName": "John Smith"
}
Invalid:
json{
"firstName": "John",
"lastName": "Smith",
"fullName": "John Smith"
}
Origin Address
Provide either:

The individual origin address components, or
originAddressFull

Do not provide both formats in the same request.
Destination Address
Provide either:

The individual destination address components, or
destinationAddressFull

Do not provide both formats in the same request.
Supported Fields

The source guide presents field names in PascalCase, while its JSON example uses camelCase. The tables below use camelCase to match the sample payload. Confirm exact casing with SmartMoving if the API rejects otherwise valid fields.

Customer Information
JSON fieldRequiredTypeRules and descriptionfirstNameConditionalStringRequired when fullName is not supplied. Submit with lastName.lastNameConditionalStringRequired when fullName is not supplied. Submit with firstName.fullNameConditionalStringRequired when firstName and lastName are not supplied.phoneNumberNoStringCustomer contact phone number.userOptInNo, recommendedBoolean or source-compatible valueRecommended when collecting phone numbers for text messaging.extensionNoStringPhone extension.phoneTypeNoString enumAllowed values: Mobile, Home, Office, Other.emailNoStringCustomer email address.
Move Information
JSON fieldRequiredTypeRules and descriptionmoveDateNoStringExpected move date. The guide specifies YYYYMMDD, for example 20190501. See the source inconsistency note below.bedroomsNoStringDescription of the number of bedrooms or rooms.moveSizeNoStringShould match a value in SmartMoving Move Size settings. A nonmatching value creates a new Move Size automatically.notesNoStringFree-form lead notes.referralSourceNoStringShould exactly match a configured referral source. See Referral Source.branchIdNoString or integer identifierSmartMoving ID for the branch. Branch IDs are available in SmartMoving settings.serviceTypeNoString enumMust be one of the supported values listed below.leadCostNoNumberIncluded in the source JSON example, although it is not described in the supported-fields list.
Allowed serviceType Values
textMoving
Packing
MovingAndPacking
LoadOnly
UnloadOnly
Commercial
StorageInBound
StorageOutBound
InnerHouse
JunkRemoval
LaborOnly
Origin Address Fields
Use either the component fields or originAddressFull, not both.
JSON fieldRequiredTypeDescriptionoriginStreetNoStringStreet portion of the origin address.originCityNoStringCity portion of the origin address.originStateNoStringState or region portion of the origin address.originZipNoStringPostal code portion of the origin address.originAddressFullNoStringFull origin address. Only use when component fields are not submitted.
Destination Address Fields
Use either the component fields or destinationAddressFull, not both.
JSON fieldRequiredTypeDescriptiondestinationStreetNoStringStreet portion of the destination address.destinationCityNoStringCity portion of the destination address.destinationStateNoStringState or region portion of the destination address.destinationZipNoStringPostal code portion of the destination address.destinationAddressFullNoStringFull destination address. Only use when component fields are not submitted.
UTM Tracking Fields
The API supports optional UTM fields for advertising and campaign attribution.
JSON fieldDescriptionutmAdGroupIdentifies the ad group within a campaign.utmCampaignIdentifies the marketing campaign.utmContentDifferentiates ads or links that point to the same URL.utmCustomTrackingStores custom tracking parameters not covered by standard UTM fields.utmKeywordIdentifies the keyword associated with an ad or paid-search campaign.utmMediumIdentifies the marketing medium, such as email, social, or cpc.utmSourceIdentifies the traffic source, such as a search engine, newsletter, or referral site.

The original guide labels one field as -UtmCustom Tracking- with a space. utmCustomTracking is used here as the normalized JSON-style name, but the exact accepted API key should be confirmed before production use.

Custom Fields
Fields not included in the supported-field list may still be submitted.
SmartMoving adds these custom fields and their values to the created lead's Notes section.
Example:
json{
"firstName": "John",
"lastName": "Smith",
"originNumberOfFloors": "2"
}
In this example, SmartMoving should capture the custom field originNumberOfFloors and its value as part of the lead note.
Referral Source
The optional referralSource field can identify where a lead originated, such as:
textGoogle
Word of Mouth
Rules:

The submitted value should exactly match the description of an existing referral source in SmartMoving.
If the value does not match an existing referral source, SmartMoving automatically creates a new referral-source record.
Restrict form users to a predefined list of referral sources.
Avoid unrestricted free-text referral-source input because it can create many unwanted referral-source records.
When referralSource is omitted, SmartMoving displays Your Website as the lead's referral source.

Configure referral sources at:
textSettings > Sales > Referral Sources
Example Request
bashcurl --request POST \
 --url "https://api.smartmoving.com/api/leads/from-provider/v2?providerKey=YOUR_PROVIDER_KEY" \
 --header "Content-Type: application/json" \
 --data '{
"firstName": "John",
"lastName": "Smith",
"phoneNumber": "555-555-5555",
"extension": "",
"userOptIn": true,
"phoneType": "Mobile",
"email": "test@example.com",
"moveDate": "20200725",
"leadCost": 12.50,
"originStreet": "123 Main Street",
"originCity": "Dallas",
"originState": "TX",
"originZip": "75208",
"destinationStreet": "",
"destinationCity": "",
"destinationState": "",
"destinationZip": "",
"bedrooms": "5 rooms",
"serviceType": "MovingAndPacking",
"notes": "We need moving and packing.",
"customField": "This is a custom field."
}'
Source JSON Sample
The following sample preserves the values and structure from the source guide:
json{
"firstName": "John Smith",
"lastName": "Dummy",
"fullName": null,
"phoneNumber": "555-555-5555",
"extension": "",
"userOptIn": "true",
"email": "test@dummy.com",
"moveDate": "7/25/2020",
"leadCost": 12.5,
"originStreet": "123 Main Street",
"originCity": "Dallas",
"originState": "TX",
"originZip": "75208",
"destinationStreet": "",
"destinationCity": "",
"destinationState": "",
"destinationZip": "",
"bedrooms": "5 rooms",
"notes": "We need moving and packing",
"customField": "This is a custom field"
}
Source Inconsistencies and Implementation Cautions
The source guide contains several details that should be verified during implementation:

Move-date format

The field description requires YYYYMMDD.
The source sample uses 7/25/2020.
Prefer YYYYMMDD unless SmartMoving confirms another accepted format.

Boolean representation

The source sample submits "userOptIn": "true" as a string.
A JSON boolean would normally be submitted as "userOptIn": true.
Confirm which representation SmartMoving accepts.

Field-name casing

The field list uses names such as FirstName.
The source JSON sample uses firstName.
Use the casing expected by the live API.

leadCost

This property appears in the JSON sample but is not described in the supported-fields section.

UTM custom tracking

The source labels the field UtmCustom Tracking, which is not a conventional JSON property name.
Confirm the exact API key.

Sample first name

The source sample sets firstName to "John Smith" and lastName to "Dummy".
In a normal submission, firstName should contain only the first name and lastName should contain only the last name.

Error Handling
The API may return an error. The submitting form or integration should:

Detect unsuccessful HTTP responses.
Show a recoverable error state.
Allow the user to resubmit.
Send an internal notification when submission fails.
Preserve a separate copy of the lead data.

Duplicate Submission Error
SmartMoving rejects duplicate submissions with:
httpHTTP 400 Bad Request
Error message:
textThis lead has already been submitted. Please contact SmartMoving support
When this specific error occurs, inform the user that their information has already been received rather than asking them to submit repeatedly.
Recommended Reliability Practices
Email Copies
Send an email copy of every form submission in addition to posting it to the SmartMoving API.
This provides a backup when:

The website cannot reach SmartMoving.
SmartMoving returns an error.
A network or integration failure occurs.

Monitoring
Implement internal notification or logging for:

Non-2xx API responses
Network failures
Invalid JSON
Duplicate submissions
Unexpected response bodies

Security

Keep the provider key out of browser-side code when possible.
Submit leads through a trusted server-side endpoint.
Do not commit provider keys to public source-control repositories.
Log failures without exposing sensitive customer information or secret keys.

These security recommendations are implementation best practices added for AI and developer use; they were not explicitly stated in the source guide.

Suggested Server-Side Processing Flow

Receive and validate the website form.
Require either:

firstName plus lastName, or
fullName.

Reject requests that provide both name formats.
Validate phoneType and serviceType against their allowed values.
Validate that origin and destination addresses do not mix full-address and component formats.
Normalize moveDate to YYYYMMDD.
Send an email backup copy.
POST the flat JSON payload to SmartMoving.
Handle successful, duplicate, validation, and network responses separately.
Store enough internal status information to investigate failed submissions safely.

Pseudocode
textvalidate input

if fullName exists and (firstName or lastName exists):
reject request

if fullName is missing and either firstName or lastName is missing:
reject request

if originAddressFull exists and any origin component exists:
reject request

if destinationAddressFull exists and any destination component exists:
reject request

if phoneType exists and is not allowed:
reject request

if serviceType exists and is not allowed:
reject request

send backup email

POST flat JSON payload to SmartMoving

if response is successful:
show confirmation
else if response is HTTP 400 and body indicates duplicate:
tell user the lead was already received
else:
log failure
notify integration owner
allow retry
Sample Form Reference
The source guide references this jQuery example:
texthttps://codepen.io/anon/pen/NoXdwj
AI Implementation Checklist
Before generating integration code, confirm or request:

Provider key handling method
Server-side language or framework
Exact SmartMoving field-name casing
Accepted moveDate format
Accepted userOptIn type
Branch-routing requirement
Form field mappings
Referral-source options
UTM parameter mappings
Backup-email destination
Failure-notification mechanism

Do not invent a provider key, branch ID, or referral-source value.
