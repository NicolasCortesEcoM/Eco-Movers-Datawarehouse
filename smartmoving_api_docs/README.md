# SmartMoving External API - Endpoint Reference

> Scraped on 2026-06-22 20:34:28  
> **Total endpoints:** 65  
> **API base URL:** `https://api-public.smartmoving.com/v1`

## Categories

| Category | Endpoints | Folder |
|----------|-----------|--------|
| basic | 26 | [basic/README.md](basic/README.md) |
| customers | 4 | [customers/README.md](customers/README.md) |
| general | 2 | [general/README.md](general/README.md) |
| jobs | 2 | [jobs/README.md](jobs/README.md) |
| leads | 5 | [leads/README.md](leads/README.md) |
| opportunities | 23 | [opportunities/README.md](opportunities/README.md) |
| premium | 3 | [premium/README.md](premium/README.md) |

## Quick Endpoint Index

| Method | Path | Category | Title |
|--------|------|----------|-------|
| `GET` | `https://api-public.smartmoving.com/v1/api/affiliates[?Page][&PageSize][&referralSourceId][&branchId]` | basic | Get affiliates |
| `GET` | `https://api-public.smartmoving.com/v1/api/arrival-windows[?Page][&PageSize]` | basic | Get arrival windows |
| `GET` | `https://api-public.smartmoving.com/v1/api/bad-lead-reasons[?Page][&PageSize]` | basic | Get bad lead reasons |
| `GET` | `https://api-public.smartmoving.com/v1/api/branches[?Page][&PageSize]` | basic | Get branches |
| `GET` | `https://api-public.smartmoving.com/v1/api/cancellation-reasons[?Page][&PageSize]` | basic | Get cancellation reasons |
| `GET` | `https://api-public.smartmoving.com/v1/api/crew-members/{crewMemberId}` | basic | Get crew member by Id |
| `GET` | `https://api-public.smartmoving.com/v1/api/crew-members/{crewMemberId}/jobs[?From][&To][&Page][&PageSize]` | basic | Get jobs by crew member id |
| `GET` | `https://api-public.smartmoving.com/v1/api/crew-members[?Page][&PageSize][&Status][&BranchId]` | basic | Get crew members |
| `GET` | `https://api-public.smartmoving.com/v1/api/customers/{customerId}` | basic | Get customer by Id |
| `GET` | `https://api-public.smartmoving.com/v1/api/customers/{customerId}/opportunities[?Page][&PageSize]` | basic | Get opportunities by customer Id |
| `GET` | `https://api-public.smartmoving.com/v1/api/customers/{customerId}/storage-accounts[?Page][&PageSize]` | basic | Get storage accounts by customer Id |
| `GET` | `https://api-public.smartmoving.com/v1/api/customers[?Page][&PageSize][&FromServiceDate][&ToServiceDate][&IncludeOpportunityInfo]` | basic | Get all customers |
| `GET` | `https://api-public.smartmoving.com/v1/api/leads/statuses` | basic | Get statuses |
| `GET` | `https://api-public.smartmoving.com/v1/api/leads/{leadId}` | basic | Get lead by Id |
| `GET` | `https://api-public.smartmoving.com/v1/api/leads[?Page][&PageSize][&From][&To][&IncludeBad][&IncludeLost]` | basic | Get leads |
| `GET` | `https://api-public.smartmoving.com/v1/api/lost-reasons[?Page][&PageSize]` | basic | Get lost lead/opportunity reasons |
| `GET` | `https://api-public.smartmoving.com/v1/api/move-sizes[?Page][&PageSize]` | basic | Get move sizes |
| `GET` | `https://api-public.smartmoving.com/v1/api/opportunities/quote/{quoteNumber}[?IncludeTripInfo][&IncludePayments][&IncludeSurveys][&IncludeJobAddresses][&IncludeTasks][&IncludeFiles][&IncludePhotos][&IncludeDocuments][&IncludeCharges][&IncludeDispatchInfo]` | basic | Get opportunity details by quote number |
| `GET` | `https://api-public.smartmoving.com/v1/api/opportunities/{opportunityId}/audit-activity` | basic | Get audit activity for opportunity |
| `GET` | `https://api-public.smartmoving.com/v1/api/opportunities/{opportunityId}/jobs` | basic | Get jobs by opportunityId |
| `GET` | `https://api-public.smartmoving.com/v1/api/opportunities/{opportunityId}[?IncludeTripInfo][&IncludePayments][&IncludeSurveys][&IncludeJobAddresses][&IncludeTasks][&IncludeFiles][&IncludePhotos][&IncludeDocuments][&IncludeCharges][&IncludeDispatchInfo]` | basic | Get opportunity details |
| `GET` | `https://api-public.smartmoving.com/v1/api/payments/opportunities/{opportunityId}` | basic | Get payments by opportunity Id |
| `GET` | `https://api-public.smartmoving.com/v1/api/referral-sources[?Page][&PageSize][&includePrivate][&includeLeadProviders]` | basic | Get referral sources |
| `GET` | `https://api-public.smartmoving.com/v1/api/service-types[?Page][&PageSize]` | basic | Get service types |
| `GET` | `https://api-public.smartmoving.com/v1/api/tariffs[?Page][&PageSize][&IncludeDisabled][&IncludeTechMate]` | basic | Get tariffs |
| `GET` | `https://api-public.smartmoving.com/v1/api/users[?Page][&PageSize]` | basic | Get users |
| `GET` | `https://api-public.smartmoving.com/v1/api/premium/customers/search[?searchQuery]` | customers | Search customers by name, email address or phone number |
| `GET` | `https://api-public.smartmoving.com/v1/api/premium/customers/{customerId}/service-tickets[?Page][&PageSize]` | customers | Get service tickets by customer Id |
| `POST` | `https://api-public.smartmoving.com/v1/api/premium/customers` | customers | Create a customer |
| `PUT` | `https://api-public.smartmoving.com/v1/api/premium/customers/{customerId}` | customers | Update a customer |
| `GET` | `https://api-public.smartmoving.com/v1/api/ping` | general | /api/ping - GET |
| `POST` | `` | general | Add attachment to opportunity |
| `PATCH` | `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/jobs/{jobId}/notes` | jobs | Update job notes |
| `PUT` | `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/jobs/{jobId}/stops` | jobs | Update job stops |
| `GET` | `https://api-public.smartmoving.com/v1/api/premium/leads/sales/{salesPersonId}[?Page][&PageSize]` | leads | Get leads by sales person Id |
| `PATCH` | `https://api-public.smartmoving.com/v1/api/premium/leads/{leadId}` | leads | Partially update lead |
| `POST` | `https://api-public.smartmoving.com/v1/api/premium/leads` | leads | Create a lead |
| `PUT` | `https://api-public.smartmoving.com/v1/api/premium/lead/{id}/convert` | leads | Convert lead to opportunity |
| `PUT` | `https://api-public.smartmoving.com/v1/api/premium/leads/{leadId}` | leads | Update lead |
| `DELETE` | `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/followups/{followupId}` | opportunities | Delete follow-up by id |
| `DELETE` | `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/inventory/rooms/{roomId}/items/{inventoryItemId}[?changeVolumeWeightCalculationMode][&markAsNeedsReview]` | opportunities | Remove opportunity inventory |
| `DELETE` | `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/jobs/{jobId}` | opportunities | Delete job |
| `GET` | `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/documents` | opportunities | Get documents |
| `GET` | `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/followups` | opportunities | Get follow-ups |
| `GET` | `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/followups/{followupId}` | opportunities | Get follow-up by id |
| `GET` | `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/inventory` | opportunities | Get opportunity inventory |
| `GET` | `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/jobs/{jobId}[?IncludeEstimatedCharges][&IncludeActualCharges][&IncludeEstimatedMaterials][&IncludeActualMaterials][&IncludeStops][&IncludeDispatchInfo][&IncludeCharges][&IncludeNotes]` | opportunities | Get job by id |
| `GET` | `https://api-public.smartmoving.com/v1/api/premium/payments/storage-accounts/{storageAccountId}` | opportunities | Get payments by storage account Id |
| `PATCH` | `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}` | opportunities | Update opportunity properties |
| `POST` | `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/Estimated/jobs/{jobId}/materials` | opportunities | Add materials to job |
| `POST` | `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/communication/calls` | opportunities | Log calls on an opportunity |
| `POST` | `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/communication/notes` | opportunities | Log notes in an opportunity |
| `POST` | `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/followups` | opportunities | Create follow-up |
| `POST` | `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/followups/{followupId}/mark-complete` | opportunities | Mark follow-up completed |
| `POST` | `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/inventory/rooms/{roomId}[?changeVolumeWeightCalculationMode][&markAsNeedsReview]` | opportunities | Add inventory to an opportunity |
| `POST` | `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/inventory/submit` | opportunities | Request inventory review |
| `POST` | `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/jobs` | opportunities | Create job |
| `POST` | `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/jobs/{jobId}/confirm[?category]` | opportunities | Confirm a job |
| `POST` | `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/rooms` | opportunities | Create rooms |
| `POST` | `https://api-public.smartmoving.com/v1/api/premium/opportunity` | opportunities | Create an opportunity |
| `PUT` | `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/followups/{followupId}` | opportunities | Update follow-up |
| `PUT` | `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/inventory/rooms/{roomId}/items/{inventoryItemId}[?changeVolumeWeightCalculationMode][&markAsNeedsReview]` | opportunities | Update opportunity inventory |
| `GET` | `https://api-public.smartmoving.com/v1/api/premium/inventory[?Page][&PageSize]` | premium | Get master inventory list |
| `GET` | `https://api-public.smartmoving.com/v1/api/premium/room-types[?Page][&PageSize]` | premium | Get room types |
| `GET` | `https://api-public.smartmoving.com/v1/api/premium/tariffs/{tariffId}/materials[?Page][&PageSize]` | premium | Get materials by tariff id |