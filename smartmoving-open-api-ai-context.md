title: "SmartMoving Open API"
document_type: "product_knowledge_base"
source_author: "Michelle Carone"
source_date: "2026-05-19"
product: "SmartMoving"
feature: "Open API"
audience:

"AI assistants"
"Developers"
"SmartMoving administrators"
"Operations teams"
access_requirement: "SmartMoving Growth Plan"
last_normalized: "2026-07-16"

SmartMoving Open API
Overview
SmartMoving's Open API is a developer-facing interface that allows external software to exchange data with SmartMoving.
An API, or Application Programming Interface, is a standardized set of rules and protocols that lets software applications communicate. An open API is made available for developers to connect applications, automate tasks, and share data between systems.
SmartMoving's Open API is available to customers on the Growth Plan.
Common Use Cases
Custom reporting dashboards
Connect SmartMoving data to analytics and visualization tools such as Tableau or Power BI.
Typical users include:

Sales teams
Accounting teams
Operations teams

Project management automation
Send new leads and booked moves to project management tools such as Monday.com or Asana.
Possible automations include:

Creating tasks
Starting workflows
Assigning work based on job details
Notifying team members

Phone system integration
Connect phone systems such as RingCentral to SmartMoving.
For example, an incoming caller's phone number can be matched to an existing SmartMoving customer record so the call can be routed appropriately.
Messaging notifications
Send alerts for new leads to collaboration tools such as Slack or Microsoft Teams.
This can help teams respond quickly and collaborate on estimates.
Lead import automation
Import leads from third-party sources directly into SmartMoving to reduce manual data entry.
Getting Started
Enable the API

In SmartMoving, go to Settings > Integrations > SmartMoving API.
Turn on the API.
Copy the generated API key.

The API key is used to authenticate requests.
Authentication
Every API request must include the API key in the x-api-key request header.
Example:
bashcurl -X GET "https://<smartmoving-external-api>/api/customers/Page=1&PageSize=10" \
 -H "Content-Type: application/json" \
 -H "x-api-key: <API_KEY>"
Replace:

<smartmoving-external-api> with the correct SmartMoving external API host.
<API_KEY> with the API key generated in SmartMoving.

Security note: Treat the API key as a secret. Do not expose it in public repositories, browser-side code, screenshots, or shared documentation.

Developer Reference
The SmartMoving API Developer Portal contains:

Available endpoints
Request formats
Response formats
Authentication requirements
Supported operations
Feature-specific implementation details

Use the developer portal as the authoritative reference when constructing requests.

The source material references the SmartMoving API Developer Portal but does not include its URL.

API Access Tiers
FeatureBasicPremiumPrimary purposeData extraction and reportingFull integration and automationMonthly call quota20,000 calls125,000 callsEndpoint accessRead-onlyRead, create, update, and deleteWebhooksNot includedIncludedPriceFree$149 per month
Choosing a tier
Choose Basic when the main goal is to:

Export SmartMoving data
Build reports
Connect to analytics tools
Use read-only endpoints

Choose Premium when the main goal is to:

Automate workflows
Send data into SmartMoving
Create, update, or delete records
Use webhooks
Build two-way integrations

For account-specific guidance, contact the SmartMoving account representative.
API Usage Alerts
For Premium accounts without automated call-pack purchases enabled, SmartMoving emails:

The company owner
Active webhook users

Alerts are sent when monthly API usage reaches:

90% of the quota
100% of the quota

Each alert includes a link to the API management page, where users can:

Purchase a one-time call pack
Enable automated call-pack purchases

Each threshold alert is sent once per billing cycle. Alert thresholds reset on the first day of each month.
Webhooks
Availability: Premium tier only.
Webhooks allow SmartMoving to push data to an external system when an event occurs.
Possible webhook categories include:

Leads
Jobs
Payments
Documents
Customers
Other supported SmartMoving events

Example uses:

Send a new lead to a CRM.
Trigger a project-management workflow.
Notify another system after a payment or job update.

Create a webhook

Go to Settings > Integrations > SmartMoving API > Webhooks.
Select Add New Webhook.
Enter the callback URL.
Complete the webhook configuration.

Review webhook call history
Go to Settings > External API > Webhooks and open the Call History drawer.
The drawer displays recent calls for each webhook from the previous seven days.
Available actions and details include:

Filter by Success or Failed
View status
View timestamp
View error message
View JSON payload

Use call history to confirm that a webhook is firing or to troubleshoot failed deliveries.
Managing API Usage
Every API request counts toward the monthly quota.
The API Usage page is located at:
Settings > Integrations > SmartMoving API
The page includes the following information.
Metrics row
Displays:

Current API tier
Current monthly call limit
Calls made during the current month
Link to API documentation

Call usage chart
A two-segment progress bar shows API consumption.

The left segment represents calls included with the plan.
For Premium users, the right segment represents calls from purchased call packs.

How Call Quotas Work
Basic tier
When the monthly quota is reached:

API access stops until the next billing cycle.
No automatic overage is applied.

Upgrading from Basic to Premium resets the quota immediately.
Premium tier
Premium users can:

Purchase additional call packs manually
Enable automated call-pack purchases

Integration designers should account for quota usage, especially for frequent polling or large-volume requests.
Buying Additional Call Packs
Availability: Premium tier only.
Unused calls from purchased packs carry over to the next month.
Purchase procedure

Open the API Usage page.
Go to the Buy Call Packs section.
Select between one and five packs.

The default selection is one pack.

Select the buy button.

The button displays the selected quantity and total cost.

Review the confirmation modal.

Quantity
Calls added
Total cost

Select Confirm to complete the purchase.
Select Cancel to close the modal without purchasing.

After confirmation:

The Additional Calls meter updates immediately.
A success notification appears.
The account is charged for the selected packs.

Automated Call-Pack Purchases
Availability: Premium tier only.
Automated purchasing adds call capacity when usage is running low.
Enable automated purchases

Open the API Usage page.
Find the Automated Purchase toggle.
Turn the toggle on.
Confirm the change in the modal.

Automatic purchase behavior
When enabled:

One additional pack is purchased when included monthly usage reaches 90%.
Another pack is purchased if remaining purchased-pack capacity falls below 10%, approximately 10,000 calls.
Only one pack is added per trigger.
Each automatically added pack is charged to the account.

Disable automated purchases

Turn the Automated Purchase toggle off.
Confirm the change in the modal.

When automated purchases are disabled and the included monthly limit is reached, API requests fail until:

The next billing cycle begins, or
A call pack is purchased manually.

Implementation Responsibilities
The Open API provides integration capabilities, but implementation requires technical expertise.
The customer's team is responsible for:

Integration design
Development
Testing
Deployment
Monitoring
Maintenance
API quota management

SmartMoving does not build custom integrations or provide implementation support.
Organizations without in-house development resources may be able to use no-code automation platforms such as Zapier, depending on the required workflow and available connectors.
Open API vs. Lead API
The Lead API is separate from the Open API.
Use the Lead API when the only requirement is to send leads into SmartMoving from:

A custom website form
A third-party lead provider
Another lead source

The Lead API:

Is free
Is available on all SmartMoving plans
Does not require an Open API subscription
Is designed specifically for lead capture

Use the Open API for broader data access, reporting, automation, system integration, and webhook workflows.
Decision Guide
RequirementRecommended optionSend website leads into SmartMovingLead APIImport leads from a third-party source onlyLead API may be sufficientExport data for dashboardsOpen API BasicBuild read-only reporting integrationsOpen API BasicCreate or update SmartMoving recordsOpen API PremiumBuild two-way integrationsOpen API PremiumReceive event-based notificationsOpen API Premium with webhooksExceed Premium's included monthly quotaPurchase call packs or enable automated purchases
Important Constraints

Open API access requires the SmartMoving Growth Plan.
Basic API access is read-only.
Webhooks require Premium API access.
Every request counts against the monthly quota.
Basic access stops when the quota is exhausted.
Premium overage capacity must be purchased manually or through automated purchases.
API keys must be included in the x-api-key header.
SmartMoving does not implement custom integrations for customers.
The Lead API should be used instead of the Open API for simple lead capture.

AI Answering Guidance
When answering questions from this document:

Distinguish clearly between the Open API and the Lead API.
Do not claim that Basic supports create, update, delete, or webhooks.
Do not claim that unused included monthly calls carry over.

Only unused calls from purchased packs are stated to carry over.

Do not invent the SmartMoving API host or Developer Portal URL.
Treat the Developer Portal as the source of truth for endpoint-level details.
Mention the Growth Plan requirement when discussing Open API availability.
Explain that implementation is the customer's responsibility.
Recommend Premium for write operations, webhooks, or full workflow automation.
Recommend Basic for read-only reporting and data extraction.
Recommend the Lead API for simple website or third-party lead capture.

Terminology
TermMeaningAPIApplication Programming InterfaceOpen APISmartMoving's general-purpose integration APIAPI keySecret value used in the x-api-key request headerEndpointA specific API URL used to access a resource or operationWebhookEvent-driven HTTP notification sent by SmartMoving to another systemCall quotaMaximum number of API requests available during a billing periodCall packAdditional API request capacity purchased by Premium usersLead APISeparate free integration for submitting leads to SmartMoving
