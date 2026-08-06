title: "SmartMoving Open API - Complete Endpoint Reference"
document_type: "api_reference"
audience:

"AI coding assistants"
"Developers building on the SmartMoving CRM"
api_name: "SmartMoving External API"
api_version: "v1"
base_url: "https://api-public.smartmoving.com/v1"
total_endpoints: 65
source: "Scraped from developer.smartmoving.com on 2026-06-22; consolidated 2026-07-16"

SmartMoving Open API - Complete Endpoint Reference
This is a single-file, self-contained reference for all 65 endpoints of the SmartMoving
External API (v1). It is written to be dropped into an AI project as context: every endpoint
below includes its method, path, tier, parameters, request body, response shape and status
codes, with no need to open another file.
Read this first: the Conventions and Data-quality caveats
sections explain the pagination envelope, the {} enum placeholders, and the handful of
scrape artifacts. Getting those wrong is the most common source of broken SmartMoving
integrations.
Contents

Quick facts
Authentication
Tiers, quotas and what you are allowed to call
Conventions
The data model
Master endpoint index
Endpoint reference
Common recipes
Data-quality caveats
Related APIs

Quick facts
Base URLhttps://api-public.smartmoving.com/v1Authx-api-key: <API_KEY> header on every requestFormatJSON in, JSON out (Content-Type: application/json)Versionv1 (baked into the base URL)Total endpoints65Plan requirementSmartMoving Growth PlanDeveloper portalhttps://developer.smartmoving.com/api-details#api=public-api-v1
Endpoint counts by category:
CategoryCountTierbasic26Basic (read-only)opportunities23Premiumleads5Premiumcustomers4Premiumpremium3Premiumgeneral2Mixedjobs2Premium

Authentication
Every request carries the API key in the x-api-key header. There is no OAuth, no bearer
token, no refresh flow, and no per-user identity - the key authenticates the company.
bashcurl -X GET "https://api-public.smartmoving.com/v1/api/customers?Page=1&PageSize=10" \
 -H "Content-Type: application/json" \
 -H "x-api-key: $SMARTMOVING_API_KEY"
To obtain the key: Settings > Integrations > SmartMoving API, turn the API on, and copy
the generated key.
Because the key is company-wide and long-lived, treat it as a high-value secret: keep it in
an environment variable or secret manager, never in browser-side code, never in a public
repo, and never in a screenshot. Rotating the key invalidates every integration using it at
once, so plan rotations deliberately.
Use GET /api/ping to verify a key works before running anything else.

Tiers, quotas and what you are allowed to call
BasicPremiumPurposeData extraction and reportingFull integration and automationMonthly call quota20,000125,000Endpoint accessRead-only (GET)Read, create, update, deleteWebhooksNot includedIncludedPriceFree$149 / month
The rule that matters when writing code: anything whose path contains /api/premium/,
and anything that is not a GET, requires the Premium tier. Of the 65 endpoints, 26 are
callable on Basic - all of them GETs under the plain /api/ prefix.
Every request counts against the monthly quota, including ones that return errors and
including pagination follow-ups. A nightly full sync that walks 50 pages of customers costs
50 calls, not 1. Budget accordingly and prefer date-filtered queries over full re-syncs.
When Basic exhausts its quota, API access stops until the next billing cycle - there is no
overage. Premium can buy call packs manually or enable automated purchases (one pack added
at 90% of included usage, another when purchased capacity drops below ~10%). Unused calls
from purchased packs carry over; unused included monthly calls do not.
Usage alerts email the company owner and active webhook users at 90% and 100% of quota, once
per billing cycle, resetting on the 1st.

Conventions
Pagination
Every list endpoint takes Page and PageSize query parameters and returns the same
envelope. Note the parameter is Page (not PageNumber) but the response field is
pageNumber:
json{
"pageNumber": 0,
"pageSize": 0,
"lastPage": true,
"totalPages": 0,
"totalResults": 0,
"totalThisPage": 0,
"pageResults": [ ]
}
Loop until lastPage is true. Do not compute your own stop condition from
totalResults - records can be created while you page.
pythondef paginate(session, path, params=None):
params = dict(params or {})
params["Page"] = 1
while True:
r = session.get(BASE + path, params=params, timeout=30)
r.raise_for_status()
body = r.json()
for row in body["pageResults"]:
yield row
if body["lastPage"]:
return
params["Page"] += 1
Casing
Query parameters are inconsistently cased in the source docs and this reference preserves
exactly what was documented. Most are PascalCase (Page, PageSize, FromServiceDate,
IncludeBad) but several are camelCase (referralSourceId, branchId, includePrivate,
searchQuery, changeVolumeWeightCalculationMode). Response and request-body fields are
always camelCase. Copy the casing from each endpoint's table rather than assuming.
Dates
Date handling is the single biggest trap in this API and it is not uniform:

Date filters and service dates on the Open API are integers in YYYYMMDD form  - 
20260519, not "2026-05-19". This includes serviceDate in opportunity responses,
which is typed 0 in the samples precisely because it is a number.
Timestamps such as createdAtUtc are strings and UTC.
The separate Lead API also uses YYYYMMDD for moveDate.

When in doubt, send YYYYMMDD and parse _Utc fields as ISO strings.
Identifiers
All IDs are opaque strings (GUIDs). You cannot construct them; you must look them up from
the reference-list endpoints. This is why the Basic GET lists matter so much - before you
can create a lead or an opportunity you need real branchId, referralSourceId,
moveSizeId, serviceTypeId, tariffId and salesPersonId values. Cache these lists;
they change rarely.
The one human-facing identifier is quoteNumber on an opportunity, which has its own
lookup endpoint (GET /api/opportunities/quote/{quoteNumber}).
Include_ flags
The heavyweight read endpoints (GET /api/opportunities/{opportunityId},
GET /api/opportunities/quote/{quoteNumber}, GET /api/premium/opportunities/{opportunityId}/jobs/{jobId})
default to a lean payload and expand only what you ask for via Include\* booleans. Request
only the blocks you need - each one costs response size and server time, and the flags do
not change the quota cost of the call.
Errors
CodeWhen you'll see itWhat to do200Success (62 of 65 endpoints document it) - 201Created (lead/customer creation)Read the new ID from the body400Validation failure (41 endpoints document it)Fix the payload; do not retry unchanged404Unknown IDResolve the ID before retrying500Server-side failure (10 endpoints document it)Retry with backoff
The docs do not publish a 401/403 shape for a bad key, nor a 429 rate-limit response
or documented rate-limit headers - the quota is enforced monthly rather than per-second.
Build backoff around 5xx and treat any non-2xx as a hard stop for 4xx.

The data model
Understanding the object graph makes the endpoint list far easier to navigate:
Customer  - - - -< Opportunity  - - - -< Job  - - - -< Stop
 - -  - -  - " - - - -< Material / Charge
 - -  - - - - - -< Follow-up
 - -  - - - - - -< Inventory Room  - - - -< Inventory Item
 - -  - - - - - -< Document / Attachment / Photo
 - -  - - - - - -< Communication (call / note)
 - -  - " - - - -< Payment
 - - - - - -< Storage Account  - - - -< Payment
 - " - - - -< Service Ticket

Lead  - - - -(convert) - - - -> Opportunity
The lifecycle in practice:

A Lead enters the system (via the Open API, the free Lead API, or the UI).
The lead is converted into an Opportunity (PUT /api/premium/lead/{id}/convert),
which creates or links a Customer.
The opportunity carries one or more Jobs, each with Stops (origin, destination
and anything between), Materials and Charges.
Inventory hangs off the opportunity, organised into Rooms containing Items.
Jobs get confirmed; Payments are recorded against the opportunity or a storage
account.

Nearly every Premium write path is nested under an opportunity, so opportunityId is the
key you will thread through most of your code.

Master endpoint index
#MethodPathTierTitle1POST(not captured)PremiumAdd attachment to opportunity2GET/api/pingBasic/api/ping - GET3GET/api/affiliatesBasicGet affiliates4GET/api/arrival-windowsBasicGet arrival windows5GET/api/bad-lead-reasonsBasicGet bad lead reasons6GET/api/branchesBasicGet branches7GET/api/cancellation-reasonsBasicGet cancellation reasons8GET/api/crew-membersBasicGet crew members9GET/api/crew-members/{crewMemberId}BasicGet crew member by Id10GET/api/crew-members/{crewMemberId}/jobsBasicGet jobs by crew member id11GET/api/customersBasicGet all customers12GET/api/customers/{customerId}BasicGet customer by Id13GET/api/customers/{customerId}/opportunitiesBasicGet opportunities by customer Id14GET/api/customers/{customerId}/storage-accountsBasicGet storage accounts by customer Id15GET/api/leadsBasicGet leads16GET/api/leads/statusesBasicGet statuses17GET/api/leads/{leadId}BasicGet lead by Id18GET/api/lost-reasonsBasicGet lost lead/opportunity reasons19GET/api/move-sizesBasicGet move sizes20GET/api/opportunities/quote/{quoteNumber}BasicGet opportunity details by quote number21GET/api/opportunities/{opportunityId}BasicGet opportunity details22GET/api/opportunities/{opportunityId}/audit-activityBasicGet audit activity for opportunity23GET/api/opportunities/{opportunityId}/jobsBasicGet jobs by opportunityId24GET/api/payments/opportunities/{opportunityId}BasicGet payments by opportunity Id25GET/api/referral-sourcesBasicGet referral sources26GET/api/service-typesBasicGet service types27GET/api/tariffsBasicGet tariffs28GET/api/usersBasicGet users29POST/api/premium/customersPremiumCreate a customer30GET/api/premium/customers/searchPremiumSearch customers by name, email address or phone number31PUT/api/premium/customers/{customerId}PremiumUpdate a customer32GET/api/premium/customers/{customerId}/service-ticketsPremiumGet service tickets by customer Id33PUT/api/premium/lead/{id}/convertPremiumConvert lead to opportunity34POST/api/premium/leadsPremiumCreate a lead35GET/api/premium/leads/sales/{salesPersonId}PremiumGet leads by sales person Id36PATCH/api/premium/leads/{leadId}PremiumPartially update lead37PUT/api/premium/leads/{leadId}PremiumUpdate lead38PATCH/api/premium/opportunities/{opportunityId}PremiumUpdate opportunity properties39POST/api/premium/opportunities/{opportunityId}/Estimated/jobs/{jobId}/materialsPremiumAdd materials to job40POST/api/premium/opportunities/{opportunityId}/communication/callsPremiumLog calls on an opportunity41POST/api/premium/opportunities/{opportunityId}/communication/notesPremiumLog notes in an opportunity42GET/api/premium/opportunities/{opportunityId}/documentsPremiumGet documents43GET/api/premium/opportunities/{opportunityId}/followupsPremiumGet follow-ups44POST/api/premium/opportunities/{opportunityId}/followupsPremiumCreate follow-up45DELETE/api/premium/opportunities/{opportunityId}/followups/{followupId}PremiumDelete follow-up by id46GET/api/premium/opportunities/{opportunityId}/followups/{followupId}PremiumGet follow-up by id47PUT/api/premium/opportunities/{opportunityId}/followups/{followupId}PremiumUpdate follow-up48POST/api/premium/opportunities/{opportunityId}/followups/{followupId}/mark-completePremiumMark follow-up completed49GET/api/premium/opportunities/{opportunityId}/inventoryPremiumGet opportunity inventory50POST/api/premium/opportunities/{opportunityId}/inventory/rooms/{roomId}PremiumAdd inventory to an opportunity51DELETE/api/premium/opportunities/{opportunityId}/inventory/rooms/{roomId}/items/{inventoryItemId}PremiumRemove opportunity inventory52PUT/api/premium/opportunities/{opportunityId}/inventory/rooms/{roomId}/items/{inventoryItemId}PremiumUpdate opportunity inventory53POST/api/premium/opportunities/{opportunityId}/inventory/submitPremiumRequest inventory review54POST/api/premium/opportunities/{opportunityId}/jobsPremiumCreate job55DELETE/api/premium/opportunities/{opportunityId}/jobs/{jobId}PremiumDelete job56GET/api/premium/opportunities/{opportunityId}/jobs/{jobId}PremiumGet job by id57POST/api/premium/opportunities/{opportunityId}/jobs/{jobId}/confirmPremiumConfirm a job58POST/api/premium/opportunities/{opportunityId}/roomsPremiumCreate rooms59POST/api/premium/opportunityPremiumCreate an opportunity60GET/api/premium/payments/storage-accounts/{storageAccountId}PremiumGet payments by storage account Id61PATCH/api/premium/opportunities/{opportunityId}/jobs/{jobId}/notesPremiumUpdate job notes62PUT/api/premium/opportunities/{opportunityId}/jobs/{jobId}/stopsPremiumUpdate job stops63GET/api/premium/inventoryPremiumGet master inventory list64GET/api/premium/room-typesPremiumGet room types65GET/api/premium/tariffs/{tariffId}/materialsPremiumGet materials by tariff id

Endpoint reference
General
Connectivity check and file attachment.

1. Add attachment to opportunity
   httpPOST /api/premium/opportunities/{opportunityId}/attachments # INFERRED - not captured by the scrape
   TierPremiumCategorygeneralOperation idpost-api-premium-opportunities-opportunityid-attachmentsFull URLnot captured - see caveat 2

Unverified. The source scrape did not capture this endpoint's path or a
complete body sample. The path above is inferred from the operation id and the
body sample below is truncated mid-field. Confirm both against the developer
portal before calling it.

Request body (application/json)
json{
"base64Contents": "string",
"fileName": "string",
"category": {}
// NOTE: truncated in the source docs - incomplete, verify against the portal
Official docs

2. /api/ping - GET
   httpGET /api/ping
   TierBasicCategorygeneralOperation idget-api-pingFull URLhttps://api-public.smartmoving.com/v1/api/ping
   ping
   Responses
   CodeMeaning200OK
   Official docs

Basic (read-only reference & reporting data)
Everything under /api/... that is a plain GET. Available on the Basic tier and up. This is where all your reporting, list-lookup and ID-resolution calls live. 3. Get affiliates
httpGET /api/affiliates
TierBasicCategorybasicOperation idget-api-affiliatesFull URLhttps://api-public.smartmoving.com/v1/api/affiliates
Get all of your account's affiliates. Optionally filter by referral source or branch.
Query parameters
NameTypeRequiredDescriptionPageintegerno - PageSizeintegerno - referralSourceIdstringno - branchIdstringno - 
Responses
CodeMeaning200OK
Response body
json{
"pageNumber": 0,
"pageSize": 0,
"lastPage": true,
"totalPages": 0,
"totalResults": 0,
"totalThisPage": 0,
"pageResults": [{
"id": "string",
"name": "string",
"company": "string",
"email": "string",
"phoneNumber": "string",
"branchId": "string",
"referralSourceId": "string"
}]
}
Official docs

4. Get arrival windows
   httpGET /api/arrival-windows
   TierBasicCategorybasicOperation idget-api-arrival-windowsFull URLhttps://api-public.smartmoving.com/v1/api/arrival-windows
   Get all the arrival windows that are configured for your company, including their description, start time, and end time.
   Query parameters
   NameTypeRequiredDescriptionPageintegerno - PageSizeintegerno - 
   Responses
   CodeMeaning200OK
   Response body
   json{
   "pageNumber": 0,
   "pageSize": 0,
   "lastPage": true,
   "totalPages": 0,
   "totalResults": 0,
   "totalThisPage": 0,
   "pageResults": [{
   "id": "string",
   "description": "string",
   "startTime": 0,
   "endTime": 0,
   "isDefault": true
   }]
   }
   Official docs

5. Get bad lead reasons
   httpGET /api/bad-lead-reasons
   TierBasicCategorybasicOperation idget-api-bad-lead-reasonsFull URLhttps://api-public.smartmoving.com/v1/api/bad-lead-reasons
   Get all of your company's bad lead reasons.
   Query parameters
   NameTypeRequiredDescriptionPageintegerno - PageSizeintegerno - 
   Responses
   CodeMeaning200OK
   Response body
   json{
   "pageNumber": 0,
   "pageSize": 0,
   "lastPage": true,
   "totalPages": 0,
   "totalResults": 0,
   "totalThisPage": 0,
   "pageResults": [{
   "id": "string",
   "name": "string",
   "sortOrder": 0
   }]
   }
   Official docs

6. Get branches
   httpGET /api/branches
   TierBasicCategorybasicOperation idget-api-branchesFull URLhttps://api-public.smartmoving.com/v1/api/branches
   Get all your company branches, alongside their dispatch location, and phone number.
   Query parameters
   NameTypeRequiredDescriptionPageintegerno - PageSizeintegerno - 
   Responses
   CodeMeaning200OK
   Response body
   json{
   "pageNumber": 0,
   "pageSize": 0,
   "lastPage": true,
   "totalPages": 0,
   "totalResults": 0,
   "totalThisPage": 0,
   "pageResults": [{
   "id": "string",
   "name": "string",
   "phoneNumber": "string",
   "dispatchLocation": {
   "fullAddress": "string",
   "street": "string",
   "city": "string",
   "state": "string",
   "zip": "string",
   "lat": 0,
   "lng": 0
   },
   "isPrimary": true
   }]
   }
   Official docs

7. Get cancellation reasons
   httpGET /api/cancellation-reasons
   TierBasicCategorybasicOperation idget-api-cancellation-reasonsFull URLhttps://api-public.smartmoving.com/v1/api/cancellation-reasons
   Get all of your company's job cancellation reasons.
   Query parameters
   NameTypeRequiredDescriptionPageintegerno - PageSizeintegerno - 
   Responses
   CodeMeaning200OK
   Response body
   json{
   "pageNumber": 0,
   "pageSize": 0,
   "lastPage": true,
   "totalPages": 0,
   "totalResults": 0,
   "totalThisPage": 0,
   "pageResults": [{
   "id": "string",
   "name": "string",
   "sortOrder": 0
   }]
   }
   Official docs

8. Get crew members
   httpGET /api/crew-members
   TierBasicCategorybasicOperation idget-api-crew-membersFull URLhttps://api-public.smartmoving.com/v1/api/crew-members
   Get all crew members configured in your account, including their contact information, role, branch, and compensation settings.
   Query parameters
   NameTypeRequiredDescriptionPageintegerno - PageSizeintegerno - StatusstringnoFilter by status: Active or InactiveBranchIdstringnoFilter by branch ID
   Responses
   CodeMeaning200OK
   Response body
   json{
   "pageNumber": 0,
   "pageSize": 0,
   "lastPage": true,
   "totalPages": 0,
   "totalResults": 0,
   "totalThisPage": 0,
   "pageResults": [{
   "id": "string",
   "name": "string",
   "status": "string",
   "mobile": "string",
   "email": "string",
   "role": {
   "id": "string",
   "name": "string"
   },
   "branch": {
   "id": "string",
   "name": "string"
   },
   "compensation": {
   "labor": {
   "method": "string",
   "rate": 0
   },
   "movingLaborPercentage": 0,
   "packingLaborPercentage": 0,
   "transportationPercentage": 0,
   "materialsPercentage": 0,
   "servicesPercentage": 0,
   "valuationPercentage": 0,
   "tripFees": {
   "rate": 0,
   "method": "string"
   },
   "fuelSurchargeFeesPercentage": 0,
   "prepaidStoragePercentage": 0,
   "warehouseHandlingPercentage": 0,
   "tripAndTravelPercentage": 0,
   "bulkyItemPercentage": 0,
   "shuttleFeePercentage": 0,
   "storageInTransitPercentage": 0,
   "insurancePercentage": 0,
   "tipsEnabled": true
   }
   }]
   }
   Official docs

9. Get crew member by Id
   httpGET /api/crew-members/{crewMemberId}
   TierBasicCategorybasicOperation idget-api-crew-members-crewmemberidFull URLhttps://api-public.smartmoving.com/v1/api/crew-members/{crewMemberId}
   Get the crew member details of one of the configured members in your account, including their contact information, role, branch, and compensation settings.
   Path parameters
   NameTypeRequiredDescriptioncrewMemberIdstringyes - 
   Responses
   CodeMeaning200OK400Bad Request
   Response body
   json{
   "id": "string",
   "name": "string",
   "status": "string",
   "mobile": "string",
   "email": "string",
   "role": {
   "id": "string",
   "name": "string"
   },
   "branch": {
   "id": "string",
   "name": "string"
   },
   "compensation": {
   "labor": {
   "method": "string",
   "rate": 0
   },
   "movingLaborPercentage": 0,
   "packingLaborPercentage": 0,
   "transportationPercentage": 0,
   "materialsPercentage": 0,
   "servicesPercentage": 0,
   "valuationPercentage": 0,
   "tripFees": {
   "rate": 0,
   "method": "string"
   },
   "fuelSurchargeFeesPercentage": 0,
   "prepaidStoragePercentage": 0,
   "warehouseHandlingPercentage": 0,
   "tripAndTravelPercentage": 0,
   "bulkyItemPercentage": 0,
   "shuttleFeePercentage": 0,
   "storageInTransitPercentage": 0,
   "insurancePercentage": 0,
   "tipsEnabled": true
   }
   }
   Official docs

10. Get jobs by crew member id
    httpGET /api/crew-members/{crewMemberId}/jobs
    TierBasicCategorybasicOperation idget-api-crew-members-crewmemberid-jobsFull URLhttps://api-public.smartmoving.com/v1/api/crew-members/{crewMemberId}/jobs
    Retrieve jobs associated with a specific crew member, filtered by service date.
    Path parameters
    NameTypeRequiredDescriptioncrewMemberIdstringyes - 
    Query parameters
    NameTypeRequiredDescriptionFromintegerno - Tointegerno - Pageintegerno - PageSizeintegerno - 
    Responses
    CodeMeaning200OK400Bad Request
    Response body
    json{
    "pageNumber": 0,
    "pageSize": 0,
    "lastPage": true,
    "totalPages": 0,
    "totalResults": 0,
    "totalThisPage": 0,
    "pageResults": [{
    "id": "string",
    "jobNumber": "string",
    "opportunityId": "string",
    "serviceType": {},
    "serviceDate": 0,
    "completedAtUtc": "string",
    "confirmedAtUtc": "string",
    "closedAtUtc": "string"
    }]
    }
    Official docs

11. Get all customers
    httpGET /api/customers
    TierBasicCategorybasicOperation idget-api-customersFull URLhttps://api-public.smartmoving.com/v1/api/customers
    Get a list of all customers ordered by name. Optionally, you can filter them based on the job service date associated with each customer's opportunities. When filtered using service date(s), by default the opportunity info is included, to exclude it set IncludeOpportunityInfo = False.
    Query parameters
    NameTypeRequiredDescriptionPageintegerno - PageSizeintegerno - FromServiceDateintegernoFormat: yyyyMMdd, eg. 20240831ToServiceDateintegernoFormat: yyyyMMdd, eg. 20240831IncludeOpportunityInfobooleanno - 
    Responses
    CodeMeaning200OK
    Response body
    json[{
    "id": "string",
    "opportunities": [{
    "id": "string",
    "quoteNumber": "string",
    "status": {},
    "jobs": [{
    "id": "string",
    "jobNumber": "string",
    "serviceDate": "string",
    "type": {}
    }]
    }],
    "name": "string",
    "phoneNumber": "string",
    "phoneType": {},
    "emailAddress": "string",
    "address": "string",
    "secondaryPhoneNumbers": [{
    "phoneNumber": "string",
    "phoneType": {}
    }]
    }]
    Official docs

12. Get customer by Id
    httpGET /api/customers/{customerId}
    TierBasicCategorybasicOperation idget-api-customers-customeridFull URLhttps://api-public.smartmoving.com/v1/api/customers/{customerId}
    Get single customer by Id
    Path parameters
    NameTypeRequiredDescriptioncustomerIdstringyes - 
    Responses
    CodeMeaning200OK400Bad Request
    Response body
    json{
    "id": "string",
    "name": "string",
    "phoneNumber": "string",
    "phoneType": {},
    "emailAddress": "string",
    "address": "string",
    "secondaryPhoneNumbers": [{
    "phoneNumber": "string",
    "phoneType": {}
    }]
    }
    Official docs

13. Get opportunities by customer Id
    httpGET /api/customers/{customerId}/opportunities
    TierBasicCategorybasicOperation idget-api-customers-customerid-opportunitiesFull URLhttps://api-public.smartmoving.com/v1/api/customers/{customerId}/opportunities
    Get opportunities by customer Id
    Path parameters
    NameTypeRequiredDescriptioncustomerIdstringyes - 
    Query parameters
    NameTypeRequiredDescriptionPageintegerno - PageSizeintegerno - 
    Responses
    CodeMeaning200OK400Bad Request
    Response body
    json[{
    "id": "string",
    "quoteNumber": "string",
    "serviceDate": 0,
    "status": {},
    "createdAtUtc": "string"
    }]
    Official docs

14. Get storage accounts by customer Id
    httpGET /api/customers/{customerId}/storage-accounts
    TierBasicCategorybasicOperation idget-api-customers-customerid-storage-accountsFull URLhttps://api-public.smartmoving.com/v1/api/customers/{customerId}/storage-accounts
    Get storage accounts by customer Id
    Path parameters
    NameTypeRequiredDescriptioncustomerIdstringyes - 
    Query parameters
    NameTypeRequiredDescriptionPageintegerno - PageSizeintegerno - 
    Responses
    CodeMeaning200OK400Bad Request
    Response body
    json[{
    "id": "string",
    "accountNumber": "string",
    "status": {},
    "jobId": "string",
    "storageType": {},
    "storageBillingPreOrPostPay": {},
    "storageAndValuationTotal": 0,
    "totalMonthlyCharges": 0,
    "storageValuationMethod": {},
    "nextInvoiceAt": "string",
    "discounts": [{
    "name": "string",
    "storageDiscountType": {},
    "discountAmountType": {},
    "amount": 0
    }],
    "warehouseSalesTaxRate": 0,
    "warehouseName": "string"
    }]
    Official docs

15. Get leads
    httpGET /api/leads
    TierBasicCategorybasicOperation idget-api-leadsFull URLhttps://api-public.smartmoving.com/v1/api/leads
    Retrieves leads created within a time range. By default, only New and In Progress leads are returned, but Lost and Bad Leads can be included through query parameters.
    Query parameters
    NameTypeRequiredDescriptionPageintegerno - PageSizeintegerno - FromintegernoFormat: yyyyMMdd, eg. 20240831TointegernoFormat: yyyyMMdd, eg. 20240831IncludeBadbooleanno - IncludeLostbooleanno - 
    Responses
    CodeMeaning200OK
    Response body
    json{
    "pageNumber": 0,
    "pageSize": 0,
    "lastPage": true,
    "totalPages": 0,
    "totalResults": 0,
    "totalThisPage": 0,
    "pageResults": [{
    "id": "string",
    "customerName": "string",
    "emailAddress": "string",
    "referralSource": "string",
    "referralSourceName": "string",
    "affiliateId": "string",
    "affiliateName": "string",
    "phoneNumber": "string",
    "phoneType": {},
    "serviceDate": 0,
    "salesPersonId": "string",
    "salesPerson": "string",
    "type": {},
    "branchId": "string",
    "branchName": "string",
    "originAddressFull": "string",
    "originStreet": "string",
    "originCity": "string",
    "originState": "string",
    "originZip": "string",
    "destinationAddressFull": "string",
    "destinationStreet": "string",
    "destinationCity": "string",
    "destinationState": "string",
    "destinationZip": "string",
    "moveSizeId": "string",
    "status": {},
    "lostReason": "string",
    "moveSizeName": "string",
    "createdAtUtc": "string"
    }]
    }
    Official docs

16. Get statuses
    httpGET /api/leads/statuses
    TierBasicCategorybasicOperation idget-api-leads-statusesFull URLhttps://api-public.smartmoving.com/v1/api/leads/statuses
    Get statuses
    Responses
    CodeMeaning200OK
    Response body
    json[{
    "id": "string",
    "customerName": "string",
    "emailAddress": "string",
    "referralSource": "string",
    "referralSourceName": "string",
    "affiliateId": "string",
    "affiliateName": "string",
    "phoneNumber": "string",
    "phoneType": {},
    "serviceDate": 0,
    "salesPersonId": "string",
    "salesPerson": "string",
    "type": {},
    "branchId": "string",
    "branchName": "string",
    "originAddressFull": "string",
    "originStreet": "string",
    "originCity": "string",
    "originState": "string",
    "originZip": "string",
    "destinationAddressFull": "string",
    "destinationStreet": "string",
    "destinationCity": "string",
    "destinationState": "string",
    "destinationZip": "string",
    "moveSizeId": "string",
    "status": {},
    "lostReason": "string",
    "moveSizeName": "string",
    "createdAtUtc": "string"
    }]
    Official docs

17. Get lead by Id
    httpGET /api/leads/{leadId}
    TierBasicCategorybasicOperation idget-api-leads-leadidFull URLhttps://api-public.smartmoving.com/v1/api/leads/{leadId}
    Get single lead by Id
    Path parameters
    NameTypeRequiredDescriptionleadIdstringyes - 
    Responses
    CodeMeaning200OK400Bad Request
    Response body
    json{
    "id": "string",
    "customerName": "string",
    "emailAddress": "string",
    "referralSource": "string",
    "referralSourceName": "string",
    "affiliateId": "string",
    "affiliateName": "string",
    "phoneNumber": "string",
    "phoneType": {},
    "serviceDate": 0,
    "salesPersonId": "string",
    "salesPerson": "string",
    "type": {},
    "branchId": "string",
    "branchName": "string",
    "originAddressFull": "string",
    "originStreet": "string",
    "originCity": "string",
    "originState": "string",
    "originZip": "string",
    "destinationAddressFull": "string",
    "destinationStreet": "string",
    "destinationCity": "string",
    "destinationState": "string",
    "destinationZip": "string",
    "moveSizeId": "string",
    "status": {},
    "lostReason": "string",
    "moveSizeName": "string",
    "createdAtUtc": "string"
    }
    Official docs

18. Get lost lead/opportunity reasons
    httpGET /api/lost-reasons
    TierBasicCategorybasicOperation idget-api-lost-reasonsFull URLhttps://api-public.smartmoving.com/v1/api/lost-reasons
    Get all of your company's lost lead/opportunity reasons.
    Query parameters
    NameTypeRequiredDescriptionPageintegerno - PageSizeintegerno - 
    Responses
    CodeMeaning200OK
    Response body
    json{
    "pageNumber": 0,
    "pageSize": 0,
    "lastPage": true,
    "totalPages": 0,
    "totalResults": 0,
    "totalThisPage": 0,
    "pageResults": [{
    "id": "string",
    "description": "string"
    }]
    }
    Official docs

19. Get move sizes
    httpGET /api/move-sizes
    TierBasicCategorybasicOperation idget-api-move-sizesFull URLhttps://api-public.smartmoving.com/v1/api/move-sizes
    Get all the move sizes that are stored in your company, alongside their description, cubic feet, and weight.
    Query parameters
    NameTypeRequiredDescriptionPageintegerno - PageSizeintegerno - 
    Responses
    CodeMeaning200OK
    Response body
    json{
    "pageNumber": 0,
    "pageSize": 0,
    "lastPage": true,
    "totalPages": 0,
    "totalResults": 0,
    "totalThisPage": 0,
    "pageResults": [{
    "id": "string",
    "name": "string",
    "description": "string",
    "volume": 0,
    "weight": 0
    }]
    }
    Official docs

20. Get opportunity details by quote number
    httpGET /api/opportunities/quote/{quoteNumber}
    TierBasicCategorybasicOperation idget-api-opportunities-quote-quotenumberFull URLhttps://api-public.smartmoving.com/v1/api/opportunities/quote/{quoteNumber}
    Get detailed information about an opportunity
    Path parameters
    NameTypeRequiredDescriptionquoteNumberintegeryes - 
    Query parameters
    NameTypeRequiredDescriptionIncludeTripInfobooleanno - IncludePaymentsbooleanno - IncludeSurveysbooleanno - IncludeJobAddressesbooleannoList of job's addresses/stops, returned in the order they were stored going from Origin, to Destination.IncludeTasksbooleanno - IncludeFilesbooleanno - IncludePhotosbooleanno - IncludeDocumentsbooleanno - IncludeChargesbooleanno - IncludeDispatchInfobooleanno - 
    Responses
    CodeMeaning200OK400Bad Request
    Response body
    json{
    "id": "string",
    "quoteNumber": 0,
    "customer": {
    "id": "string",
    "name": "string",
    "emailAddress": "string",
    "phoneNumber": "string",
    "phoneType": {}
    },
    "branch": {
    "name": "string",
    "phoneNumber": "string"
    },
    "contacts": [{
    "name": "string",
    "emailAddress": "string",
    "phoneNumber": "string",
    "phoneType": {}
    }],
    "opportunityType": {},
    "type": {},
    "serviceDate": 0,
    "status": {},
    "leadStatus": "string",
    "moveSize": {
    "name": "string",
    "description": "string",
    "volume": 0
    },
    "volume": 0,
    "weight": 0,
    "volumeWeightCalculationMode": {},
    "estimatedTotal": {
    "subtotal": 0,
    "taxableAmount": 0,
    "tax": 0,
    "finalTotal": 0
    },
    "estimator": {
    "name": "string",
    "mobileNumber": "string",
    "branchId": "string",
    "regionId": "string",
    "title": "string"
    },
    "salesAssignee": {
    "id": "string",
    "name": "string"
    },
    "hasTripInfo": true,
    "referralSource": "string",
    "affiliateId": "string",
    "affiliateName": "string",
    "allowInventoryUpdates": true,
    "customField01": "string",
    "customField02": "string",
    "customField03": "string",
    "cancellationReason": "string",
    "jobs": [{
    "id": "string",
    "jobNumber": "string",
    "jobDate": 0,
    "type": {},
    "confirmed": true,
    "jobAddresses": ["string"],
    "jobDocuments": [{
    "title": "string",
    "type": {},
    "isComplete": true
    }],
    "estimatedCharges": [{
    "name": "string",
    "chargeCategory": 0,
    "description": "string",
    "editableDescription": "string",
    "sortOrder": 0,
    "subtotal": 0,
    "discountAmount": 0,
    "totalCost": 0
    }],
    "actualCharges": [{
    "name": "string",
    "chargeCategory": 0,
    "description": "string",
    "editableDescription": "string",
    "sortOrder": 0,
    "subtotal": 0,
    "discountAmount": 0,
    "totalCost": 0
    }],
    "arrivalWindow": {
    "id": "string",
    "description": "string",
    "startTime": 0,
    "endTime": 0,
    "isDefault": true
    },
    "totalTips": 0,
    "crewMembers": ["string"],
    "jobTime": {
    "laborTime": {
    "estimated": 0,
    "actual": 0
    },
    "billableHours": 0,
    "travelTime": {
    "estimated": 0,
    "actual": 0
    }
    }
    }],
    "payments": [{
    "source": {},
    "paymentType": {},
    "amount": 0,
    "takenByUser": "string",
    "isOutstanding": true,
    "paidAtUtc": "string",
    "refundsJobPaymentId": "string",
    "amountRefunded": 0,
    "paymentCategory": {}
    }],
    "tripInfo": {
    "isTripInfoApplied": true,
    "pickupSpreadFirstAvailableDate": 0,
    "pickupSpreadLastAvailableDate": 0,
    "confirmedPickupDate": 0,
    "preferredPickupTime": 0,
    "preferredPickupTimeDurationMinutes": 0,
    "deliverySpreadFirstAvailableDate": 0,
    "deliverySpreadLastAvailableDate": 0,
    "confirmedDeliveryDate": 0,
    "preferredDeliveryTime": 0,
    "preferredDeliveryTimeDurationMinutes": 0
    },
    "opportunityFiles": ["string"],
    "photos": ["string"],
    "opportunityDocuments": [{
    "title": "string",
    "type": {},
    "isComplete": true
    }],
    "surveys": [{
    "assignedTo": {
    "name": "string",
    "mobileNumber": "string",
    "branchId": "string",
    "regionId": "string",
    "title": "string"
    },
    "type": {},
    "title": "string",
    "startAtUtc": "string",
    "durationMinutes": 0,
    "notes": "string",
    "isConfirmed": true
    }],
    "tasks": [{
    "title": "string",
    "customer": {
    "id": "string",
    "name": "string",
    "emailAddress": "string",
    "phoneNumber": "string",
    "phoneType": {}
    },
    "assignedTo": {
    "name": "string",
    "mobileNumber": "string",
    "branchId": "string",
    "regionId": "string",
    "title": "string"
    },
    "taskItemType": {},
    "taskItemStatus": {},
    "notes": "string"
    }],
    "tariff": {
    "id": "string",
    "name": "string"
    },
    "createdAtUtc": "string"
    }
    Official docs

21. Get opportunity details
    httpGET /api/opportunities/{opportunityId}
    TierBasicCategorybasicOperation idget-api-opportunities-opportunityidFull URLhttps://api-public.smartmoving.com/v1/api/opportunities/{opportunityId}
    Get detailed information about an opportunity
    Path parameters
    NameTypeRequiredDescriptionopportunityIdstringyes - 
    Query parameters
    NameTypeRequiredDescriptionIncludeTripInfobooleanno - IncludePaymentsbooleanno - IncludeSurveysbooleanno - IncludeJobAddressesbooleannoList of job's addresses/stops, returned in the order they were stored going from Origin, to Destination.IncludeTasksbooleanno - IncludeFilesbooleanno - IncludePhotosbooleanno - IncludeDocumentsbooleanno - IncludeChargesbooleanno - IncludeDispatchInfobooleanno - 
    Responses
    CodeMeaning200OK400Bad Request
    Response body
    json{
    "id": "string",
    "quoteNumber": 0,
    "customer": {
    "id": "string",
    "name": "string",
    "emailAddress": "string",
    "phoneNumber": "string",
    "phoneType": {}
    },
    "branch": {
    "name": "string",
    "phoneNumber": "string"
    },
    "contacts": [{
    "name": "string",
    "emailAddress": "string",
    "phoneNumber": "string",
    "phoneType": {}
    }],
    "opportunityType": {},
    "type": {},
    "serviceDate": 0,
    "status": {},
    "leadStatus": "string",
    "moveSize": {
    "name": "string",
    "description": "string",
    "volume": 0
    },
    "volume": 0,
    "weight": 0,
    "volumeWeightCalculationMode": {},
    "estimatedTotal": {
    "subtotal": 0,
    "taxableAmount": 0,
    "tax": 0,
    "finalTotal": 0
    },
    "estimator": {
    "name": "string",
    "mobileNumber": "string",
    "branchId": "string",
    "regionId": "string",
    "title": "string"
    },
    "salesAssignee": {
    "id": "string",
    "name": "string"
    },
    "hasTripInfo": true,
    "referralSource": "string",
    "affiliateId": "string",
    "affiliateName": "string",
    "allowInventoryUpdates": true,
    "customField01": "string",
    "customField02": "string",
    "customField03": "string",
    "cancellationReason": "string",
    "jobs": [{
    "id": "string",
    "jobNumber": "string",
    "jobDate": 0,
    "type": {},
    "confirmed": true,
    "jobAddresses": ["string"],
    "jobDocuments": [{
    "title": "string",
    "type": {},
    "isComplete": true
    }],
    "estimatedCharges": [{
    "name": "string",
    "chargeCategory": 0,
    "description": "string",
    "editableDescription": "string",
    "sortOrder": 0,
    "subtotal": 0,
    "discountAmount": 0,
    "totalCost": 0
    }],
    "actualCharges": [{
    "name": "string",
    "chargeCategory": 0,
    "description": "string",
    "editableDescription": "string",
    "sortOrder": 0,
    "subtotal": 0,
    "discountAmount": 0,
    "totalCost": 0
    }],
    "arrivalWindow": {
    "id": "string",
    "description": "string",
    "startTime": 0,
    "endTime": 0,
    "isDefault": true
    },
    "totalTips": 0,
    "crewMembers": ["string"],
    "jobTime": {
    "laborTime": {
    "estimated": 0,
    "actual": 0
    },
    "billableHours": 0,
    "travelTime": {
    "estimated": 0,
    "actual": 0
    }
    }
    }],
    "payments": [{
    "source": {},
    "paymentType": {},
    "amount": 0,
    "takenByUser": "string",
    "isOutstanding": true,
    "paidAtUtc": "string",
    "refundsJobPaymentId": "string",
    "amountRefunded": 0,
    "paymentCategory": {}
    }],
    "tripInfo": {
    "isTripInfoApplied": true,
    "pickupSpreadFirstAvailableDate": 0,
    "pickupSpreadLastAvailableDate": 0,
    "confirmedPickupDate": 0,
    "preferredPickupTime": 0,
    "preferredPickupTimeDurationMinutes": 0,
    "deliverySpreadFirstAvailableDate": 0,
    "deliverySpreadLastAvailableDate": 0,
    "confirmedDeliveryDate": 0,
    "preferredDeliveryTime": 0,
    "preferredDeliveryTimeDurationMinutes": 0
    },
    "opportunityFiles": ["string"],
    "photos": ["string"],
    "opportunityDocuments": [{
    "title": "string",
    "type": {},
    "isComplete": true
    }],
    "surveys": [{
    "assignedTo": {
    "name": "string",
    "mobileNumber": "string",
    "branchId": "string",
    "regionId": "string",
    "title": "string"
    },
    "type": {},
    "title": "string",
    "startAtUtc": "string",
    "durationMinutes": 0,
    "notes": "string",
    "isConfirmed": true
    }],
    "tasks": [{
    "title": "string",
    "customer": {
    "id": "string",
    "name": "string",
    "emailAddress": "string",
    "phoneNumber": "string",
    "phoneType": {}
    },
    "assignedTo": {
    "name": "string",
    "mobileNumber": "string",
    "branchId": "string",
    "regionId": "string",
    "title": "string"
    },
    "taskItemType": {},
    "taskItemStatus": {},
    "notes": "string"
    }],
    "tariff": {
    "id": "string",
    "name": "string"
    },
    "createdAtUtc": "string"
    }
    Official docs

22. Get audit activity for opportunity
    httpGET /api/opportunities/{opportunityId}/audit-activity
    TierBasicCategorybasicOperation idget-api-opportunities-opportunityid-audit-activityFull URLhttps://api-public.smartmoving.com/v1/api/opportunities/{opportunityId}/audit-activity
    Get audit activity for opportunity
    Path parameters
    NameTypeRequiredDescriptionopportunityIdstringyes - 
    Responses
    CodeMeaning200OK400Bad Request
    Response body
    json[{
    "id": "string",
    "activityType": {},
    "description": "string",
    "changeMadeByUserId": "string",
    "createdAtUtc": "string"
    }]
    Official docs

23. Get jobs by opportunityId
    httpGET /api/opportunities/{opportunityId}/jobs
    TierBasicCategorybasicOperation idget-api-opportunities-opportunityid-jobsFull URLhttps://api-public.smartmoving.com/v1/api/opportunities/{opportunityId}/jobs
    Get jobs by Opportunity Id
    Path parameters
    NameTypeRequiredDescriptionopportunityIdstringyes - 
    Responses
    CodeMeaning200OK400Bad Request
    Response body
    json[{
    "id": "string",
    "type": {},
    "jobNumber": "string",
    "jobDate": 0,
    "startTimeUtc": "string",
    "endTimeUtc": "string",
    "completedAtUtc": "string",
    "confirmedAtUtc": "string",
    "closedAtUtc": "string"
    }]
    Official docs

24. Get payments by opportunity Id
    httpGET /api/payments/opportunities/{opportunityId}
    TierBasicCategorybasicOperation idget-api-payments-opportunities-opportunityidFull URLhttps://api-public.smartmoving.com/v1/api/payments/opportunities/{opportunityId}
    Get opportunity payments by opportunity Id
    Path parameters
    NameTypeRequiredDescriptionopportunityIdstringyes - 
    Responses
    CodeMeaning200OK400Bad Request
    Response body
    json[{
    "id": "string",
    "opportunityId": "string",
    "jobId": "string",
    "source": {},
    "paymentType": {},
    "amount": 0,
    "takenByUserId": "string",
    "createdAtUtc": "string",
    "customPaymentDescription": "string",
    "gatewayPaymentId": "string",
    "refundsJobPaymentId": "string",
    "amountRefunded": 0,
    "paymentCategory": {},
    "isRefund": true
    }]
    Official docs

25. Get referral sources
    httpGET /api/referral-sources
    TierBasicCategorybasicOperation idget-api-referral-sourcesFull URLhttps://api-public.smartmoving.com/v1/api/referral-sources
    Get all of your account's referral sources, with the option to retrieve all of them or only your public ones (users on public lead forms you might have embedded on your website). If desired, you can also include your active lead providers in the response.
    Query parameters
    NameTypeRequiredDescriptionPageintegerno - PageSizeintegerno - includePrivatebooleanno - includeLeadProvidersbooleanno - 
    Responses
    CodeMeaning200OK
    Response body
    json{
    "pageNumber": 0,
    "pageSize": 0,
    "lastPage": true,
    "totalPages": 0,
    "totalResults": 0,
    "totalThisPage": 0,
    "pageResults": [{
    "id": "string",
    "name": "string",
    "isLeadProvider": true,
    "isPublic": true
    }]
    }
    Official docs

26. Get service types
    httpGET /api/service-types
    TierBasicCategorybasicOperation idget-api-service-typesFull URLhttps://api-public.smartmoving.com/v1/api/service-types
    Get all your enabled service types, both system and custom ones.
    Query parameters
    NameTypeRequiredDescriptionPageintegerno - PageSizeintegerno - 
    Responses
    CodeMeaning200OK
    Response body
    json{
    "pageNumber": 0,
    "pageSize": 0,
    "lastPage": true,
    "totalPages": 0,
    "totalResults": 0,
    "totalThisPage": 0,
    "pageResults": [{
    "id": {},
    "name": "string",
    "scalingFactorPercentage": 0,
    "hasActivityLoading": true,
    "hasActivityFinishedLoading": true,
    "hasActivityUnloading": true,
    "order": 0
    }]
    }
    Official docs

27. Get tariffs
    httpGET /api/tariffs
    TierBasicCategorybasicOperation idget-api-tariffsFull URLhttps://api-public.smartmoving.com/v1/api/tariffs
    Get all the tariffs within your company, with the option to include disabled tariffs or not.
    Query parameters
    NameTypeRequiredDescriptionPageintegerno - PageSizeintegerno - IncludeDisabledbooleanno - IncludeTechMatebooleannoInclude external tariffs created on TechMate in the response.
    Responses
    CodeMeaning200OK
    Response body
    json{
    "pageNumber": 0,
    "pageSize": 0,
    "lastPage": true,
    "totalPages": 0,
    "totalResults": 0,
    "totalThisPage": 0,
    "pageResults": [{
    "id": "string",
    "name": "string",
    "isEnabled": true,
    "appliesToOpportunityTypes": [0],
    "appliesToBranches": [{
    "branchId": "string",
    "branchName": "string"
    }]
    }]
    }
    Official docs

28. Get users
    httpGET /api/users
    TierBasicCategorybasicOperation idget-api-usersFull URLhttps://api-public.smartmoving.com/v1/api/users
    Get all the office users in your company, with all their key descriptive attributes such as title and role. Crew members are not included.
    Query parameters
    NameTypeRequiredDescriptionPageintegerno - PageSizeintegerno - 
    Responses
    CodeMeaning200OK
    Response body
    json{
    "pageNumber": 0,
    "pageSize": 0,
    "lastPage": true,
    "totalPages": 0,
    "totalResults": 0,
    "totalThisPage": 0,
    "pageResults": [{
    "id": "string",
    "name": "string",
    "title": "string",
    "email": "string",
    "primaryBranch": {
    "id": "string",
    "name": "string"
    },
    "role": {
    "id": "string",
    "name": "string"
    }
    }]
    }
    Official docs

Customers
Create, update and search customer records, plus their service tickets. All Premium. 29. Create a customer
httpPOST /api/premium/customers
TierPremiumCategorycustomersOperation idpost-api-premium-customersFull URLhttps://api-public.smartmoving.com/v1/api/premium/customers
Create a customer
Request body (application/json)
json{
"name": "string",
"phoneNumber": "string",
"phoneType": {},
"emailAddress": "string",
"address": "string",
"secondaryPhoneNumbers": [{
"phoneNumber": "string",
"phoneType": {}
}]
}
Responses
CodeMeaning200OK
Returns: Customer Id
Official docs

30. Search customers by name, email address or phone number
    httpGET /api/premium/customers/search
    TierPremiumCategorycustomersOperation idget-api-premium-customers-searchFull URLhttps://api-public.smartmoving.com/v1/api/premium/customers/search
    Search customers by name, email address or phone number
    Query parameters
    NameTypeRequiredDescriptionsearchQuerystringno - 
    Responses
    CodeMeaning200OK400Bad Request
    Response body
    json[{
    "id": "string",
    "name": "string",
    "phoneNumber": "string",
    "phoneType": {},
    "emailAddress": "string",
    "address": "string",
    "secondaryPhoneNumbers": [{
    "phoneNumber": "string",
    "phoneType": {}
    }]
    }]
    Official docs

31. Update a customer
    httpPUT /api/premium/customers/{customerId}
    TierPremiumCategorycustomersOperation idput-api-premium-customers-customeridFull URLhttps://api-public.smartmoving.com/v1/api/premium/customers/{customerId}
    Update a customer
    Path parameters
    NameTypeRequiredDescriptioncustomerIdstringyes - 
    Request body (application/json)
    json{
    "name": "string",
    "phoneNumber": "string",
    "phoneType": {},
    "emailAddress": "string",
    "address": "string",
    "secondaryPhoneNumbers": [{
    "phoneNumber": "string",
    "phoneType": {}
    }]
    }
    Responses
    CodeMeaning200OK400Bad Request
    Returns: Success
    Official docs

32. Get service tickets by customer Id
    httpGET /api/premium/customers/{customerId}/service-tickets
    TierPremiumCategorycustomersOperation idget-api-premium-customers-customerid-service-ticketsFull URLhttps://api-public.smartmoving.com/v1/api/premium/customers/{customerId}/service-tickets
    Get service tickets by customer Id
    Path parameters
    NameTypeRequiredDescriptioncustomerIdstringyes - 
    Query parameters
    NameTypeRequiredDescriptionPageintegerno - PageSizeintegerno - 
    Responses
    CodeMeaning200OK400Bad Request
    Response body
    json[{
    "id": "string",
    "jobId": "string",
    "name": "string",
    "type": {},
    "status": {},
    "priority": {},
    "createdAtUtc": "string"
    }]
    Official docs

Leads
Create, update and convert leads. All Premium. See also GET /api/leads and GET /api/leads/{leadId} in the Basic section for reading leads. 33. Convert lead to opportunity
httpPUT /api/premium/lead/{id}/convert
TierPremiumCategoryleadsOperation idput-api-premium-lead-id-convertFull URLhttps://api-public.smartmoving.com/v1/api/premium/lead/{id}/convert
Convert lead to opportunity
Path parameters
NameTypeRequiredDescriptionidstringyes - 
Request body (application/json)
json{
"customerId": "string",
"referralSourceId": "string",
"tariffId": "string",
"branchId": "string",
"moveDate": "string",
"moveSizeId": "string",
"salesPersonId": "string",
"serviceTypeId": {},
"originAddress": {
"fullAddress": "string",
"street": "string",
"unit": "string",
"city": "string",
"state": "string",
"zip": "string",
"lat": 0,
"lng": 0,
"country": "string"
},
"destinationAddress": {
"fullAddress": "string",
"street": "string",
"unit": "string",
"city": "string",
"state": "string",
"zip": "string",
"lat": 0,
"lng": 0,
"country": "string"
}
}
Responses
CodeMeaning200OK400Bad Request500Internal Server Error
Returns: Opportunity details
Official docs

34. Create a lead
    httpPOST /api/premium/leads
    TierPremiumCategoryleadsOperation idpost-api-premium-leadsFull URLhttps://api-public.smartmoving.com/v1/api/premium/leads
    Submit a new lead to SmartMoving through the Premium API. Either ReferralSource or ReferralSourceId is required. For names, provide at least one of FullName, FirstName, or LastName.
    Request body (application/json)
    json{
    "firstName": "string",
    "lastName": "string",
    "fullName": "string",
    "phoneNumber": "string",
    "extension": "string",
    "phoneType": "string",
    "email": "string",
    "moveDate": "string",
    "leadCost": 0,
    "originStreet": "string",
    "originCity": "string",
    "originState": "string",
    "originZip": "string",
    "originAddressFull": "string",
    "destinationStreet": "string",
    "destinationCity": "string",
    "destinationState": "string",
    "destinationZip": "string",
    "destinationAddressFull": "string",
    "bedrooms": "string",
    "notes": "string",
    "referralSource": "string",
    "referralSourceId": "string",
    "affiliate": "string",
    "affiliateId": "string",
    "moveSize": "string",
    "moveSizeId": "string",
    "serviceType": "string",
    "branchId": "string",
    "opportunityType": "string",
    "trackingParameters": "string",
    "userOptIn": true,
    "utmAdGroup": "string",
    "utmCampaign": "string",
    "utmContent": "string",
    "utmCustomTracking": "string",
    "utmKeyword": "string",
    "utmMedium": "string",
    "utmSource": "string"
    }
    Responses
    CodeMeaning200OK400Bad Request500Internal Server Error
    Returns: Lead created successfully
    Official docs

35. Get leads by sales person Id
    httpGET /api/premium/leads/sales/{salesPersonId}
    TierPremiumCategoryleadsOperation idget-api-premium-leads-sales-salespersonidFull URLhttps://api-public.smartmoving.com/v1/api/premium/leads/sales/{salesPersonId}
    Get leads by sales person Id
    Path parameters
    NameTypeRequiredDescriptionsalesPersonIdstringyes - 
    Query parameters
    NameTypeRequiredDescriptionPageintegerno - PageSizeintegerno - 
    Responses
    CodeMeaning200OK
    Response body
    json{
    "pageNumber": 0,
    "pageSize": 0,
    "lastPage": true,
    "totalPages": 0,
    "totalResults": 0,
    "totalThisPage": 0,
    "pageResults": [{
    "id": "string",
    "customerName": "string",
    "emailAddress": "string",
    "referralSource": "string",
    "referralSourceName": "string",
    "affiliateId": "string",
    "affiliateName": "string",
    "phoneNumber": "string",
    "phoneType": {},
    "serviceDate": 0,
    "salesPersonId": "string",
    "salesPerson": "string",
    "type": {},
    "branchId": "string",
    "branchName": "string",
    "originAddressFull": "string",
    "originStreet": "string",
    "originCity": "string",
    "originState": "string",
    "originZip": "string",
    "destinationAddressFull": "string",
    "destinationStreet": "string",
    "destinationCity": "string",
    "destinationState": "string",
    "destinationZip": "string",
    "moveSizeId": "string",
    "status": {},
    "lostReason": "string",
    "moveSizeName": "string",
    "createdAtUtc": "string"
    }]
    }
    Official docs

36. Partially update lead
    httpPATCH /api/premium/leads/{leadId}
    TierPremiumCategoryleadsOperation idpatch-api-premium-leads-leadidFull URLhttps://api-public.smartmoving.com/v1/api/premium/leads/{leadId}
    Partially update a lead by its ID with only the fields you want to change
    Path parameters
    NameTypeRequiredDescriptionleadIdstringyes - 
    Request body (application/json)
    json{
    "customerName": "string",
    "moveDate": "string",
    "utmInformation": {
    "utmAdGroup": "string",
    "utmCampaign": "string",
    "utmContent": "string",
    "utmCustomTracking": "string",
    "utmKeyword": "string",
    "utmMedium": "string",
    "utmSource": "string"
    },
    "emailAddress": "string",
    "phoneNumber": "string",
    "phoneType": {},
    "branchId": "string",
    "referralSourceId": "string",
    "salesPersonId": "string",
    "serviceTypeId": {},
    "moveSizeId": "string",
    "originAddress": {
    "fullAddress": "string",
    "street": "string",
    "unit": "string",
    "city": "string",
    "state": "string",
    "zip": "string",
    "lat": 0,
    "lng": 0,
    "country": "string"
    },
    "destinationAddress": {
    "fullAddress": "string",
    "street": "string",
    "unit": "string",
    "city": "string",
    "state": "string",
    "zip": "string",
    "lat": 0,
    "lng": 0,
    "country": "string"
    },
    "fromExternalApi": true
    }
    Responses
    CodeMeaning200OK500Internal Server Error
    Returns: Lead updated
    Official docs

37. Update lead
    httpPUT /api/premium/leads/{leadId}
    TierPremiumCategoryleadsOperation idput-api-premium-leads-leadidFull URLhttps://api-public.smartmoving.com/v1/api/premium/leads/{leadId}
    Update a lead by its ID and easily modify its details
    Path parameters
    NameTypeRequiredDescriptionleadIdstringyes - 
    Request body (application/json)
    json{
    "customerName": "string",
    "branchId": "string",
    "referralSourceId": "string",
    "moveDate": "string",
    "utmInformation": {
    "utmAdGroup": "string",
    "utmCampaign": "string",
    "utmContent": "string",
    "utmCustomTracking": "string",
    "utmKeyword": "string",
    "utmMedium": "string",
    "utmSource": "string"
    },
    "emailAddress": "string",
    "phoneNumber": "string",
    "phoneType": {},
    "salesPersonId": "string",
    "serviceTypeId": {},
    "moveSizeId": "string",
    "originAddress": {
    "fullAddress": "string",
    "street": "string",
    "unit": "string",
    "city": "string",
    "state": "string",
    "zip": "string",
    "lat": 0,
    "lng": 0,
    "country": "string"
    },
    "destinationAddress": {
    "fullAddress": "string",
    "street": "string",
    "unit": "string",
    "city": "string",
    "state": "string",
    "zip": "string",
    "lat": 0,
    "lng": 0,
    "country": "string"
    }
    }
    Responses
    CodeMeaning200OK500Internal Server Error
    Returns: Lead updated
    Official docs

Opportunities
The largest surface: opportunities, their jobs, follow-ups, inventory, communication logs, documents and payments. All Premium. 38. Update opportunity properties
httpPATCH /api/premium/opportunities/{opportunityId}
TierPremiumCategoryopportunitiesOperation idpatch-api-premium-opportunities-opportunityidFull URLhttps://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}
Update specific properties of an opportunity. Only updates properties that are provided in the request.
Path parameters
NameTypeRequiredDescriptionopportunityIdstringyes - 
Request body (application/json)
json{
"moveSizeId": "string",
"salesPersonId": "string",
"branchId": "string",
"opportunityType": {},
"volume": 0,
"weight": 0,
"isBinding": true,
"depositAmount": 0,
"referralSourceId": "string",
"affiliateId": "string",
"customField01": "string",
"customField02": "string",
"customField03": "string"
}
Responses
CodeMeaning200OK400Bad Request500Internal Server Error
Returns: Opportunity updated successfully
Official docs

39. Add materials to job
    httpPOST /api/premium/opportunities/{opportunityId}/Estimated/jobs/{jobId}/materials
    TierPremiumCategoryopportunitiesOperation idpost-api-premium-opportunities-opportunityid-estimated-jobs-jobid-materialsFull URLhttps://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/Estimated/jobs/{jobId}/materials
    Add packing materials to job based on its tariff. When using this endpoint, the materials added will overwrite the materials on the job, if there are any.
    Path parameters
    NameTypeRequiredDescriptionopportunityIdstringyes - jobIdstringyes - 
    Request body (application/json)
    json{
    "materials": [{
    "quantity": 0,
    "materialId": "string"
    }]
    }
    Responses
    CodeMeaning200OK400Bad Request
    Returns: Materials added to job
    Official docs

40. Log calls on an opportunity
    httpPOST /api/premium/opportunities/{opportunityId}/communication/calls
    TierPremiumCategoryopportunitiesOperation idpost-api-premium-opportunities-opportunityid-communication-callsFull URLhttps://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/communication/calls
    Log your calls in your opportunities to ensure your entire team stays updated on the latest events. These will appear as entries on the sales activity page.
    Path parameters
    NameTypeRequiredDescriptionopportunityIdstringyes - 
    Request body (application/json)
    json{
    "callType": {},
    "outcome": {},
    "callDateTime": "string",
    "description": "string",
    "fromNumber": "string",
    "toNumber": "string",
    "createdBy": "string"
    }
    Responses
    CodeMeaning200OK400Bad Request500Internal Server Error
    Returns: Call added to opportunity
    Official docs

41. Log notes in an opportunity
    httpPOST /api/premium/opportunities/{opportunityId}/communication/notes
    TierPremiumCategoryopportunitiesOperation idpost-api-premium-opportunities-opportunityid-communication-notesFull URLhttps://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/communication/notes
    Log notes in your opportunities to ensure your entire team stays updated on the latest events. These will appear as entries on the sales activity page.
    Path parameters
    NameTypeRequiredDescriptionopportunityIdstringyes - 
    Request body (application/json)
    json{
    "notes": "string",
    "createdBy": "string"
    }
    Responses
    CodeMeaning200OK400Bad Request500Internal Server Error
    Returns: Note added to opportunity
    Official docs

42. Get documents
    httpGET /api/premium/opportunities/{opportunityId}/documents
    TierPremiumCategoryopportunitiesOperation idget-api-premium-opportunities-opportunityid-documentsFull URLhttps://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/documents
    Get all (opportunity and job) documents for a given opportunity
    Path parameters
    NameTypeRequiredDescriptionopportunityIdstringyes - 
    Responses
    CodeMeaning200OK400Bad Request
    Response body
    json{
    "opportunityDocuments": [{
    "id": "string",
    "title": "string",
    "isComplete": true,
    "url": "string"
    }],
    "jobDocuments": [{
    "jobId": "string",
    "id": "string",
    "title": "string",
    "isComplete": true,
    "url": "string"
    }]
    }
    Official docs

43. Get follow-ups
    httpGET /api/premium/opportunities/{opportunityId}/followups
    TierPremiumCategoryopportunitiesOperation idget-api-premium-opportunities-opportunityid-followupsFull URLhttps://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/followups
    Get all follow-ups for a given opportunity
    Path parameters
    NameTypeRequiredDescriptionopportunityIdstringyes - 
    Responses
    CodeMeaning200OK400Bad Request
    Response body
    json[{
    "id": "string",
    "opportunityId": "string",
    "type": {},
    "title": "string",
    "assignedToId": "string",
    "dueDateTime": "string",
    "completedAtUtc": "string",
    "notes": "string",
    "completed": true
    }]
    Official docs

44. Create follow-up
    httpPOST /api/premium/opportunities/{opportunityId}/followups
    TierPremiumCategoryopportunitiesOperation idpost-api-premium-opportunities-opportunityid-followupsFull URLhttps://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/followups
    Create follow-up for opportunityId
    Path parameters
    NameTypeRequiredDescriptionopportunityIdstringyes - 
    Request body (application/json)
    json{
    "type": {},
    "title": "string",
    "assignedToId": "string",
    "dueDateTime": "string",
    "completedAtUtc": "string",
    "notes": "string",
    "completed": true
    }
    Responses
    CodeMeaning201Created400Bad Request
    Official docs

45. Delete follow-up by id
    httpDELETE /api/premium/opportunities/{opportunityId}/followups/{followupId}
    TierPremiumCategoryopportunitiesOperation iddelete-api-premium-opportunities-opportunityid-followups-followupidFull URLhttps://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/followups/{followupId}
    Delete single follow-up for opportunityId and follow-up Id
    Path parameters
    NameTypeRequiredDescriptionopportunityIdstringyes - followupIdstringyes - 
    Responses
    CodeMeaning200OK400Bad Request
    Returns: OK
    Official docs

46. Get follow-up by id
    httpGET /api/premium/opportunities/{opportunityId}/followups/{followupId}
    TierPremiumCategoryopportunitiesOperation idget-api-premium-opportunities-opportunityid-followups-followupidFull URLhttps://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/followups/{followupId}
    Get single follow-up for opportunityId and follow-up Id
    Path parameters
    NameTypeRequiredDescriptionopportunityIdstringyes - followupIdstringyes - 
    Responses
    CodeMeaning200OK400Bad Request
    Response body
    json{
    "id": "string",
    "opportunityId": "string",
    "type": {},
    "title": "string",
    "assignedToId": "string",
    "dueDateTime": "string",
    "completedAtUtc": "string",
    "notes": "string",
    "completed": true
    }
    Official docs

47. Update follow-up
    httpPUT /api/premium/opportunities/{opportunityId}/followups/{followupId}
    TierPremiumCategoryopportunitiesOperation idput-api-premium-opportunities-opportunityid-followups-followupidFull URLhttps://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/followups/{followupId}
    Update single follow-up for opportunityId and follow-up Id
    Path parameters
    NameTypeRequiredDescriptionopportunityIdstringyes - followupIdstringyes - 
    Request body (application/json)
    json{
    "type": {},
    "title": "string",
    "assignedToId": "string",
    "dueDateTime": "string",
    "completedAtUtc": "string",
    "notes": "string",
    "completed": true
    }
    Responses
    CodeMeaning200OK400Bad Request
    Returns: OK
    Official docs

48. Mark follow-up completed
    httpPOST /api/premium/opportunities/{opportunityId}/followups/{followupId}/mark-complete
    TierPremiumCategoryopportunitiesOperation idpost-api-premium-opportunities-opportunityid-followups-followupid-mark-complFull URLhttps://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/followups/{followupId}/mark-complete
    Mark an opportunity follow-up as completed
    Path parameters
    NameTypeRequiredDescriptionfollowupIdstringyes - opportunityIdstringyes - 
    Request body (application/json)
    json{
    "id": "string",
    "opportunityId": "string",
    "type": {},
    "title": "string",
    "assignedToId": "string",
    "dueDateTime": "string",
    "completedAtUtc": "string",
    "notes": "string",
    "completed": true
    }
    Responses
    CodeMeaning200OK400Bad Request
    Returns: Follow-up marked as complete
    Official docs

49. Get opportunity inventory
    httpGET /api/premium/opportunities/{opportunityId}/inventory
    TierPremiumCategoryopportunitiesOperation idget-api-premium-opportunities-opportunityid-inventoryFull URLhttps://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/inventory
    Get detailed information about opportunity inventory
    Path parameters
    NameTypeRequiredDescriptionopportunityIdstringyes - 
    Responses
    CodeMeaning200OK400Bad Request
    Response body
    json{
    "id": "string",
    "createdAtUtc": "string",
    "lastModifiedById": "string",
    "lastModifiedFromApplication": {},
    "densityFactor": 0,
    "boxes": [{
    "id": "string",
    "name": "string",
    "description": "string",
    "shortCode": 0,
    "notes": "string",
    "volume": 0,
    "weight": 0,
    "imageUrl": "string",
    "quantity": 0,
    "inventoryItemId": "string"
    }],
    "rooms": [{
    "id": "string",
    "name": "string",
    "description": "string",
    "roomType": "string",
    "items": [{
    "id": "string",
    "name": "string",
    "description": "string",
    "notes": "string",
    "shortCode": 0,
    "quantity": 0,
    "volume": 0,
    "weight": 0,
    "width": 0,
    "depth": 0,
    "height": 0,
    "type": {},
    "inventoryItemId": "string",
    "imageUrls": ["string"]
    }]
    }],
    "lockStatus": true
    }
    Official docs

50. Add inventory to an opportunity
    httpPOST /api/premium/opportunities/{opportunityId}/inventory/rooms/{roomId}
    TierPremiumCategoryopportunitiesOperation idpost-api-premium-opportunities-opportunityid-inventory-rooms-roomidFull URLhttps://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/inventory/rooms/{roomId}
    Add items to an existing opportunity: Include the ID if you want to add inventory from your master list, or create a custom inventory through the Name. Each custom inventory created can also be added to the master inventory list if desired.
    Path parameters
    NameTypeRequiredDescriptionopportunityIdstringyes - roomIdstringyes - 
    Query parameters
    NameTypeRequiredDescriptionchangeVolumeWeightCalculationModebooleannoIf true or not specified, the opportunity will be updated to calculate by inventory when items are added.markAsNeedsReviewbooleannoIf true or not specified, the inventory will be marked as needing review
    Request body (application/json)
    json{
    "items": [{
    "id": "string",
    "name": "string",
    "description": "string",
    "notes": "string",
    "volume": 0,
    "weight": 0,
    "quantity": 0,
    "quantityNotGoing": 0,
    "saveToMaster": false
    }]
    }
    Responses
    CodeMeaning200OK400Bad Request
    Returns: Item(s) added to room
    Official docs

51. Remove opportunity inventory
    httpDELETE /api/premium/opportunities/{opportunityId}/inventory/rooms/{roomId}/items/{inventoryItemId}
    TierPremiumCategoryopportunitiesOperation iddelete-api-premium-opportunities-opportunityid-inventory-rooms-roomid-itemsFull URLhttps://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/inventory/rooms/{roomId}/items/{inventoryItemId}
    Remove opportunity inventory
    Path parameters
    NameTypeRequiredDescriptionopportunityIdstringyes - roomIdstringyes - inventoryItemIdstringyes - 
    Query parameters
    NameTypeRequiredDescriptionchangeVolumeWeightCalculationModebooleannoIf true or not specified, the opportunity will be updated to calculate by inventory when items are deleted.markAsNeedsReviewbooleannoIf true or not specified, the inventory will be marked as needing review
    Responses
    CodeMeaning200OK400Bad Request
    Returns: Item successfully deleted
    Official docs

52. Update opportunity inventory
    httpPUT /api/premium/opportunities/{opportunityId}/inventory/rooms/{roomId}/items/{inventoryItemId}
    TierPremiumCategoryopportunitiesOperation idput-api-premium-opportunities-opportunityid-inventory-rooms-roomid-items-invFull URLhttps://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/inventory/rooms/{roomId}/items/{inventoryItemId}
    Update opportunity inventory
    Path parameters
    NameTypeRequiredDescriptionopportunityIdstringyes - roomIdstringyes - inventoryItemIdstringyes - 
    Query parameters
    NameTypeRequiredDescriptionchangeVolumeWeightCalculationModebooleannoIf true or not specified, the opportunity will be updated to calculate by inventory when items are updated.markAsNeedsReviewbooleannoIf true or not specified, the inventory will be marked as needing review
    Request body (application/json)
    json{
    "notes": "string",
    "volume": 0,
    "weight": 0,
    "quantity": 0,
    "quantityNotGoing": 0
    }
    Responses
    CodeMeaning200OK400Bad Request
    Returns: Item successfully updated
    Official docs

53. Request inventory review
    httpPOST /api/premium/opportunities/{opportunityId}/inventory/submit
    TierPremiumCategoryopportunitiesOperation idpost-api-premium-opportunities-opportunityid-inventory-submitFull URLhttps://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/inventory/submit
    Initiate an inventory review request for a specific opportunity, mirroring the functionality of the "Submit Inventory" button in the Customer Portal. Submissions can be resolved from the opportunity's Sales tab.
    Path parameters
    NameTypeRequiredDescriptionopportunityIdstringyes - 
    Request body - none captured in the source docs.
    Responses
    CodeMeaning200OK400Bad Request
    Returns: Inventory submitted successfully
    Official docs

54. Create job
    httpPOST /api/premium/opportunities/{opportunityId}/jobs
    TierPremiumCategoryopportunitiesOperation idpost-api-premium-opportunities-opportunityid-jobsFull URLhttps://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/jobs
    Create job for opportunity
    Path parameters
    NameTypeRequiredDescriptionopportunityIdstringyes - 
    Request body (application/json)
    json{
    "serviceType": {}
    }
    Responses
    CodeMeaning201Created404Not Found400Bad Request
    Official docs

55. Delete job
    httpDELETE /api/premium/opportunities/{opportunityId}/jobs/{jobId}
    TierPremiumCategoryopportunitiesOperation iddelete-api-premium-opportunities-opportunityid-jobs-jobidFull URLhttps://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/jobs/{jobId}
    Remove job from opportunity
    Path parameters
    NameTypeRequiredDescriptionopportunityIdstringyes - jobIdstringyes - 
    Responses
    CodeMeaning200OK404Not Found400Bad Request
    Returns: OK
    Official docs

56. Get job by id
    httpGET /api/premium/opportunities/{opportunityId}/jobs/{jobId}
    TierPremiumCategoryopportunitiesOperation idget-api-premium-opportunities-opportunityid-jobs-jobidFull URLhttps://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/jobs/{jobId}
    Get job details by Id
    Path parameters
    NameTypeRequiredDescriptionopportunityIdstringyes - jobIdstringyes - 
    Query parameters
    NameTypeRequiredDescriptionIncludeEstimatedChargesbooleanno - IncludeActualChargesbooleanno - IncludeEstimatedMaterialsbooleanno - IncludeActualMaterialsbooleanno - IncludeStopsbooleanno - IncludeDispatchInfobooleanno - IncludeChargesbooleanno - IncludeNotesbooleanno - 
    Responses
    CodeMeaning200OK400Bad Request
    Response body
    json{
    "opportunityId": "string",
    "arrivalWindow": "string",
    "dropOffDate": 0,
    "stops": [{
    "id": "string",
    "isOrigin": true,
    "isDestination": true,
    "order": 0,
    "addressFullAddress": "string",
    "addressLat": 0,
    "addressLng": 0,
    "addressUnit": "string",
    "propertyName": "string",
    "propertyType": {},
    "stairs": 0,
    "parkingDescription": "string",
    "hasElevator": true,
    "notes": "string"
    }],
    "estimatedCharges": [{
    "id": "string",
    "name": "string",
    "chargeCategory": {},
    "chargeType": {},
    "subtotal": 0,
    "discountAmount": 0,
    "discountPercent": 0,
    "quantity": 0,
    "totalCost": 0
    }],
    "actualCharges": [{
    "estimatedJobChargeId": "string",
    "estimatedJobCharge": {
    "id": "string",
    "name": "string",
    "chargeCategory": {},
    "chargeType": {},
    "subtotal": 0,
    "discountAmount": 0,
    "discountPercent": 0,
    "quantity": 0,
    "totalCost": 0
    },
    "id": "string",
    "name": "string",
    "chargeCategory": {},
    "chargeType": {},
    "subtotal": 0,
    "discountAmount": 0,
    "discountPercent": 0,
    "quantity": 0,
    "totalCost": 0
    }],
    "estimatedMaterials": [{
    "id": "string",
    "name": "string",
    "description": "string",
    "materialsQuantity": 0,
    "materialsRate": 0,
    "packingQuantity": 0,
    "packingRate": 0,
    "packingTimeMinutes": 0,
    "unpackingQuantity": 0,
    "unpackingRate": 0,
    "unpackingTimeMinutes": 0,
    "isContainer": true
    }],
    "actualMaterials": [{
    "id": "string",
    "name": "string",
    "description": "string",
    "materialsQuantity": 0,
    "materialsRate": 0,
    "packingQuantity": 0,
    "packingRate": 0,
    "packingTimeMinutes": 0,
    "unpackingQuantity": 0,
    "unpackingRate": 0,
    "unpackingTimeMinutes": 0,
    "isContainer": true
    }],
    "crewMembers": ["string"],
    "jobTime": {
    "laborTime": {
    "estimated": 0,
    "actual": 0
    },
    "billableHours": 0,
    "travelTime": {
    "estimated": 0,
    "actual": 0
    }
    },
    "totalTips": 0,
    "notes": {
    "crewNotes": "string",
    "customerNotes": "string",
    "internalNotes": "string",
    "crewFeedback": "string",
    "accountingNotes": "string",
    "dispatcherNotes": "string"
    },
    "id": "string",
    "type": {},
    "jobNumber": "string",
    "jobDate": 0,
    "startTimeUtc": "string",
    "endTimeUtc": "string",
    "completedAtUtc": "string",
    "confirmedAtUtc": "string",
    "closedAtUtc": "string"
    }
    Official docs

57. Confirm a job
    httpPOST /api/premium/opportunities/{opportunityId}/jobs/{jobId}/confirm
    TierPremiumCategoryopportunitiesOperation idpost-api-premium-opportunities-opportunityid-jobs-jobid-confirmFull URLhttps://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/jobs/{jobId}/confirm
    Confirm a job by jobId and category (optional)
    Path parameters
    NameTypeRequiredDescriptionopportunityIdstringyes - jobIdstringyes - 
    Query parameters
    NameTypeRequiredDescriptioncategorystringno - 
    Request body - none captured in the source docs.
    Responses
    CodeMeaning200OK400Bad Request
    Returns: OK
    Official docs

58. Create rooms
    httpPOST /api/premium/opportunities/{opportunityId}/rooms
    TierPremiumCategoryopportunitiesOperation idpost-api-premium-opportunities-opportunityid-roomsFull URLhttps://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/rooms
    Add new rooms to your lead or opportunity, and use it to load your job's inventory.
    Path parameters
    NameTypeRequiredDescriptionopportunityIdstringyes - 
    Request body (application/json)
    json[{
    "name": "string",
    "roomTypeId": "string"
    }]
    Responses
    CodeMeaning200OK400Bad Request500Internal Server Error
    Returns: Room details
    Official docs

59. Create an opportunity
    httpPOST /api/premium/opportunity
    TierPremiumCategoryopportunitiesOperation idpost-api-premium-opportunityFull URLhttps://api-public.smartmoving.com/v1/api/premium/opportunity
    Create an opportunity from scratch, indicating all the required fields. Continue to SmartMoving to get an estimate proposal sent to the customer, or retrieve the estimation from the Get opportunity details endpoint to handle the communication externally.
    Request body (application/json)
    json{
    "tariffId": "string",
    "salesPersonId": "string",
    "customerId": "string",
    "referralSourceId": "string",
    "affiliateId": "string",
    "branchId": "string",
    "moveDate": "string",
    "moveSizeId": "string",
    "serviceTypeId": {},
    "utmInformation": {
    "utmAdGroup": "string",
    "utmCampaign": "string",
    "utmContent": "string",
    "utmCustomTracking": "string",
    "utmKeyword": "string",
    "utmMedium": "string",
    "utmSource": "string"
    },
    "originAddress": {
    "fullAddress": "string",
    "street": "string",
    "unit": "string",
    "city": "string",
    "state": "string",
    "zip": "string",
    "lat": 0,
    "lng": 0,
    "country": "string"
    },
    "destinationAddress": {
    "fullAddress": "string",
    "street": "string",
    "unit": "string",
    "city": "string",
    "state": "string",
    "zip": "string",
    "lat": 0,
    "lng": 0,
    "country": "string"
    },
    "customField01": "string",
    "customField02": "string",
    "customField03": "string"
    }
    Responses
    CodeMeaning200OK400Bad Request500Internal Server Error
    Returns: Opportunity details
    Official docs

60. Get payments by storage account Id
    httpGET /api/premium/payments/storage-accounts/{storageAccountId}
    TierPremiumCategoryopportunitiesOperation idget-api-premium-payments-storage-accounts-storageaccountidFull URLhttps://api-public.smartmoving.com/v1/api/premium/payments/storage-accounts/{storageAccountId}
    Get storage payments by storage account Id
    Path parameters
    NameTypeRequiredDescriptionstorageAccountIdstringyes - 
    Responses
    CodeMeaning200OK400Bad Request
    Response body
    json[{
    "id": "string",
    "storageAccountId": "string",
    "source": {},
    "paymentType": {},
    "createdAtUtc": "string",
    "amount": 0,
    "balance": 0,
    "takenByUserId": "string",
    "description": "string",
    "gatewayPaymentId": "string",
    "refundsPaymentId": "string",
    "amountRefunded": 0,
    "isRefund": true
    }]
    Official docs

Jobs
Job notes and stops. All Premium. Job creation/deletion/confirmation live under Opportunities. 61. Update job notes
httpPATCH /api/premium/opportunities/{opportunityId}/jobs/{jobId}/notes
TierPremiumCategoryjobsOperation idpatch-api-premium-opportunities-opportunityid-jobs-jobid-notesFull URLhttps://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/jobs/{jobId}/notes
Update any of the note properties on a job such as CrewNotes, CustomerNotes, InternalNotes, AccountingNotes, or DispatcherNotes
Path parameters
NameTypeRequiredDescriptionopportunityIdstringyes - jobIdstringyes - 
Request body (application/json)
json{
"crewNotes": "string",
"customerNotes": "string",
"internalNotes": "string",
"accountingNotes": "string",
"dispatcherNotes": "string"
}
Responses
CodeMeaning200OK404Not Found500Internal Server Error
Returns: Notes updated successfully
Official docs

62. Update job stops
    httpPUT /api/premium/opportunities/{opportunityId}/jobs/{jobId}/stops
    TierPremiumCategoryjobsOperation idput-api-premium-opportunities-opportunityid-jobs-jobid-stopsFull URLhttps://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/jobs/{jobId}/stops
    Update all stops for a job
    Path parameters
    NameTypeRequiredDescriptionopportunityIdstringyes - jobIdstringyes - 
    Request body (application/json)
    json[{
    "id": "string",
    "isOrigin": true,
    "isDestination": true,
    "order": 0,
    "addressFullAddress": "string",
    "addressLat": 0,
    "addressLng": 0,
    "addressUnit": "string",
    "propertyName": "string",
    "propertyType": {},
    "stopType": {},
    "stairs": 0,
    "hasElevator": true,
    "notes": "string",
    "street": "string",
    "city": "string",
    "state": "string",
    "zip": "string",
    "county": "string"
    }]
    Responses
    CodeMeaning200OK400Bad Request404Not Found
    Returns: Updated stops
    Official docs

Premium reference data (inventory, room types, materials)
Premium-tier read-only reference lists used when building inventory and material payloads. 63. Get master inventory list
httpGET /api/premium/inventory
TierPremiumCategorypremiumOperation idget-api-premium-inventoryFull URLhttps://api-public.smartmoving.com/v1/api/premium/inventory
Get the master inventory list with all the relevant information, and use its IDs to add inventory items.
Query parameters
NameTypeRequiredDescriptionPageintegerno - PageSizeintegerno - 
Responses
CodeMeaning200OK
Response body
json{
"pageNumber": 0,
"pageSize": 0,
"lastPage": true,
"totalPages": 0,
"totalResults": 0,
"totalThisPage": 0,
"pageResults": [{
"id": "string",
"name": "string",
"description": "string",
"shortCode": 0,
"volume": 0,
"weight": 0
}]
}
Official docs

64. Get room types
    httpGET /api/premium/room-types
    TierPremiumCategorypremiumOperation idget-api-premium-room-typesFull URLhttps://api-public.smartmoving.com/v1/api/premium/room-types
    Get all the room types that are stored in your company's inventory configuration.
    Query parameters
    NameTypeRequiredDescriptionPageintegerno - PageSizeintegerno - 
    Responses
    CodeMeaning200OK
    Response body
    json{
    "pageNumber": 0,
    "pageSize": 0,
    "lastPage": true,
    "totalPages": 0,
    "totalResults": 0,
    "totalThisPage": 0,
    "pageResults": [{
    "id": "string",
    "name": "string"
    }]
    }
    Official docs

65. Get materials by tariff id
    httpGET /api/premium/tariffs/{tariffId}/materials
    TierPremiumCategorypremiumOperation idget-api-premium-tariffs-tariffid-materialsFull URLhttps://api-public.smartmoving.com/v1/api/premium/tariffs/{tariffId}/materials
    Get all your tariff's packing materials information.
    Path parameters
    NameTypeRequiredDescriptiontariffIdstringyes - 
    Query parameters
    NameTypeRequiredDescriptionPageintegerno - PageSizeintegerno - 
    Responses
    CodeMeaning200OK400Bad Request
    Response body
    json{
    "pageNumber": 0,
    "pageSize": 0,
    "lastPage": true,
    "totalPages": 0,
    "totalResults": 0,
    "totalThisPage": 0,
    "pageResults": [{
    "id": "string",
    "rate": 0,
    "name": "string",
    "description": "string",
    "packTimeInMinutes": 0,
    "unpackTimeInMinutes": 0,
    "carrierPackShortCode": 0,
    "packByOwnerShortCode": 0,
    "cost": 0,
    "volume": 0,
    "weight": 0,
    "sortOrder": 0
    }]
    }
    Official docs

Common recipes
A minimal client
pythonimport os, requests

BASE = "https://api-public.smartmoving.com/v1"

session = requests.Session()
session.headers.update({
"x-api-key": os.environ["SMARTMOVING_API_KEY"],
"Content-Type": "application/json",
})

def get(path, \*\*params):
r = session.get(BASE + path, params=params, timeout=30)
r.raise_for_status()
return r.json()

def paginate(path, **params):
params["Page"] = 1
while True:
body = get(path, **params)
yield from body["pageResults"]
if body["lastPage"]:
return
params["Page"] += 1
Resolve the reference IDs you need before writing anything
pythonbranches = {b["name"]: b["id"] for b in paginate("/api/branches", PageSize=100)}
sources = {s["name"]: s["id"] for s in paginate("/api/referral-sources", PageSize=100)}
move_sizes = {m["name"]: m["id"] for m in paginate("/api/move-sizes", PageSize=100)}
services = {s["name"]: s["id"] for s in paginate("/api/service-types", PageSize=100)}
tariffs = {t["name"]: t["id"] for t in paginate("/api/tariffs", PageSize=100)}
users = {u["name"]: u["id"] for u in paginate("/api/users", PageSize=100)}
Cache these. They are stable, and re-fetching them on every run burns quota for nothing.
Lead -' opportunity -' job
pythonlead = session.post(f"{BASE}/api/premium/leads", json={
"firstName": "Jane",
"lastName": "Doe",
"phoneNumber": "5551234567",
"email": "jane@example.com",
"moveDate": "20260901",
"originZip": "33101",
"destinationZip": "30301",
"branchId": branches["Miami"],
"referralSourceId": sources["Website"],
}).json()

opportunity = session.put(
f"{BASE}/api/premium/lead/{lead['id']}/convert",
json={
"customerId": lead["customerId"],
"branchId": branches["Miami"],
"referralSourceId": sources["Website"],
"tariffId": tariffs["Standard"],
"moveSizeId": move_sizes["2 Bedroom"],
"serviceTypeId": services["Local Move"],
"moveDate": "20260901",
},
).json()

job = session.post(
f"{BASE}/api/premium/opportunities/{opportunity['id']}/jobs",
json={"jobDate": 20260901, "serviceTypeId": services["Local Move"]},
).json()
Pull every opportunity in a service-date window
pythoncustomers = paginate(
"/api/customers",
FromServiceDate=20260701,
ToServiceDate=20260731,
IncludeOpportunityInfo=True,
PageSize=100,
)
GET /api/customers with IncludeOpportunityInfo=true is the cheapest way to sweep a date
range - it avoids an N+1 of one GET /api/customers/{id}/opportunities per customer.
Fetch one opportunity with everything expanded
pythonfull = get(
f"/api/opportunities/{opportunity_id}",
IncludeTripInfo=True,
IncludePayments=True,
IncludeSurveys=True,
IncludeJobAddresses=True,
IncludeTasks=True,
IncludeFiles=True,
IncludePhotos=True,
IncludeDocuments=True,
IncludeCharges=True,
IncludeDispatchInfo=True,
)
Build inventory
pythonroom = session.post(
f"{BASE}/api/premium/opportunities/{opp_id}/rooms",
json=[{"name": "Living Room"}],
).json()

session.post(
f"{BASE}/api/premium/opportunities/{opp_id}/inventory/rooms/{room_id}",
params={"changeVolumeWeightCalculationMode": True, "markAsNeedsReview": True},
json=[{"id": master_item_id, "quantity": 2}],
)

session.post(f"{BASE}/api/premium/opportunities/{opp_id}/inventory/submit")
Inventory items either reference a master-list id (from GET /api/premium/inventory) or
define a custom item by name. The two query flags control whether the opportunity switches
to calculating volume/weight from inventory and whether the result is flagged for review  - 
both default to true when omitted.

Data-quality caveats
This reference was generated from a scrape of the SmartMoving developer portal on
2026-06-22. The scrape is faithful about paths, methods, parameters and field names, but it
has four known gaps. Trust the portal over this document where they disagree.

1. Enums arrive as {}. Any field rendered "status": {}, "phoneType": {},
   "serviceTypeId": {}, "opportunityType": {}, "taskItemType": {}, "stopType": {},
   "propertyType": {} or similar is an enum whose allowed values the scrape did not
   capture. The field is real and usually required; only the value list is missing. Resolve
   them from the portal, from GET /api/leads/statuses, from the relevant reference list
   (/api/service-types, /api/move-sizes, /api/lost-reasons, /api/cancellation-reasons,
   /api/bad-lead-reasons, /api/arrival-windows), or by reading a real record back from your
   own account. Do not guess enum values - a wrong one is a 400.
2. Add attachment to opportunity has no captured path. Its documented URL is missing
   from the source data. From the operation id
   (post-api-premium-opportunities-opportunityid-attachments) the path is almost certainly
   POST /api/premium/opportunities/{opportunityId}/attachments, and its body sample is also
   truncated mid-field. Verify against the portal before using it.
3. Five endpoints show {opportunityId} where a body sample belongs. Confirm a job,
   Delete follow-up by id, Delete job, Remove opportunity inventory and Request inventory
   review captured a path token instead of a request body. These are scrape artifacts, and this
   document reports them as "no request body captured". The DELETEs genuinely take no body;
   the POSTs may take a small one.
4. Field types are inferred from sample values. In the samples "string" means string,
   0 means number, and true means boolean - they are type placeholders, not defaults or
   examples. A 0 on a date field means it is a numeric YYYYMMDD, not that zero is valid.

Related APIs
The Lead API is a different API. It has a different host
(https://api.smartmoving.com), different auth (a providerKey query parameter, not
x-api-key), a different version (v2), is free on every plan, and exists only to accept
inbound leads from web forms and lead providers:
POST https://api.smartmoving.com/api/leads/from-provider/v2?providerKey={provider_key}
Its payload is strictly flat - no nested customer/origin/destination objects - and only the
customer name is required. If your only requirement is "get website leads into SmartMoving",
use the Lead API and skip the Open API subscription entirely. See
smartmoving_lead_api_ai_guide.md in this repository.
Webhooks are Premium-only and push events to you instead of you polling. They cover
leads, jobs, payments, documents and customers, and are configured at
Settings > Integrations > SmartMoving API > Webhooks, with a seven-day call history
drawer for debugging. For anything event-shaped, a webhook is dramatically cheaper than
polling this API on a timer. See smartmoving_webhooks_ai_reference.md in this repository.
Implementation is the customer's responsibility. SmartMoving does not build custom
integrations or provide implementation support. Design, development, testing, deployment,
monitoring, maintenance and quota management are all on your team.
