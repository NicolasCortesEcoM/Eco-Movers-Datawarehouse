# BASIC - API Endpoints

**Total:** 26 endpoints

---

## Get affiliates

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/affiliates[?Page][&PageSize][&referralSourceId][&branchId]`  
**Description:** Get all of your account's affiliates. Optionally filter by referral source or branch.  

**Tags:** `basic`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `Page` | query | No | `integer` |  |  |
| `PageSize` | query | No | `integer` |  |  |
| `referralSourceId` | query | No | `string` |  |  |
| `branchId` | query | No | `string` |  |  |

### Responses

- **Response: 200 OK**

> Affiliates

**Sample response:**

```json
{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-affiliates](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-affiliates)

---

## Get all customers

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/customers[?Page][&PageSize][&FromServiceDate][&ToServiceDate][&IncludeOpportunityInfo]`  
**Description:** Get a list of all customers ordered by name. Optionally, you can filter them based on the job service date associated with each customer's opportunities. When filtered using service date(s), by default the opportunity info is included, to exclude it set IncludeOpportunityInfo = False.  

**Tags:** `basic` `customers`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `Page` | query | No | `integer` |  |  |
| `PageSize` | query | No | `integer` |  |  |
| `FromServiceDate` | query | No | `integer` |  | Format: yyyyMMdd, eg. 20240831 |
| `ToServiceDate` | query | No | `integer` |  | Format: yyyyMMdd, eg. 20240831 |
| `IncludeOpportunityInfo` | query | No | `boolean` |  |  |

### Responses

- **Response: 200 OK**

> Customers

**Sample response:**

```json
[{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-customers](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-customers)

---

## Get arrival windows

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/arrival-windows[?Page][&PageSize]`  
**Description:** Get all the arrival windows that are configured for your company, including their description, start time, and end time.  

**Tags:** `basic`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `Page` | query | No | `integer` |  |  |
| `PageSize` | query | No | `integer` |  |  |

### Responses

- **Response: 200 OK**

> Arrival windows

**Sample response:**

```json
{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-arrival-windows](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-arrival-windows)

---

## Get audit activity for opportunity

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/opportunities/{opportunityId}/audit-activity`  
**Description:** Get audit activity for opportunity  

**Tags:** `basic` `opportunities`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `opportunityId` | template | -... Yes | `string` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**

> Opportunity audit activity

**Sample response:**

```json
[{
    "id": "string",
    "activityType": {},
    "description": "string",
    "changeMadeByUserId": "string",
    "createdAtUtc": "string"
}]
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-opportunities-opportunityid-audit-activity](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-opportunities-opportunityid-audit-activity)

---

## Get bad lead reasons

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/bad-lead-reasons[?Page][&PageSize]`  
**Description:** Get all of your company's bad lead reasons.  

**Tags:** `basic`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `Page` | query | No | `integer` |  |  |
| `PageSize` | query | No | `integer` |  |  |

### Responses

- **Response: 200 OK**

> Bad lead reasons

**Sample response:**

```json
{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-bad-lead-reasons](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-bad-lead-reasons)

---

## Get branches

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/branches[?Page][&PageSize]`  
**Description:** Get all your company branches, alongside their dispatch location, and phone number.  

**Tags:** `basic`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `Page` | query | No | `integer` |  |  |
| `PageSize` | query | No | `integer` |  |  |

### Responses

- **Response: 200 OK**

> branches

**Sample response:**

```json
{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-branches](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-branches)

---

## Get cancellation reasons

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/cancellation-reasons[?Page][&PageSize]`  
**Description:** Get all of your company's job cancellation reasons.  

**Tags:** `basic`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `Page` | query | No | `integer` |  |  |
| `PageSize` | query | No | `integer` |  |  |

### Responses

- **Response: 200 OK**

> Cancellation reasons

**Sample response:**

```json
{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-cancellation-reasons](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-cancellation-reasons)

---

## Get crew member by Id

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/crew-members/{crewMemberId}`  
**Description:** Get the crew member details of one of the configured members in your account, including their contact information, role, branch, and compensation settings.  

**Tags:** `basic`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `crewMemberId` | template | -... Yes | `string` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**

> Crew member

**Sample response:**

```json
{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-crew-members-crewmemberid](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-crew-members-crewmemberid)

---

## Get crew members

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/crew-members[?Page][&PageSize][&Status][&BranchId]`  
**Description:** Get all crew members configured in your account, including their contact information, role, branch, and compensation settings.  

**Tags:** `basic`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `Page` | query | No | `integer` |  |  |
| `PageSize` | query | No | `integer` |  |  |
| `Status` | query | No | `` |  | Filter by status: Active or Inactive |
| `BranchId` | query | No | `string` |  | Filter by branch ID |

### Responses

- **Response: 200 OK**

> Crew members

**Sample response:**

```json
{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-crew-members](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-crew-members)

---

## Get customer by Id

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/customers/{customerId}`  
**Description:** Get single customer by Id  

**Tags:** `basic` `customers`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `customerId` | template | -... Yes | `string` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**

> Customer

**Sample response:**

```json
{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-customers-customerid](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-customers-customerid)

---

## Get jobs by crew member id

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/crew-members/{crewMemberId}/jobs[?From][&To][&Page][&PageSize]`  
**Description:** Retrieve jobs associated with a specific crew member, filtered by service date.  

**Tags:** `basic` `crew-members`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `crewMemberId` | template | -... Yes | `string` |  |  |
| `From` | query | No | `integer` |  |  |
| `To` | query | No | `integer` |  |  |
| `Page` | query | No | `integer` |  |  |
| `PageSize` | query | No | `integer` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**

> Page result of Jobs

**Sample response:**

```json
{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-crew-members-crewmemberid-jobs](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-crew-members-crewmemberid-jobs)

---

## Get jobs by opportunityId

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/opportunities/{opportunityId}/jobs`  
**Description:** Get jobs by Opportunity Id  

**Tags:** `basic` `opportunities`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `opportunityId` | template | -... Yes | `string` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**

> Job

**Sample response:**

```json
[{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-opportunities-opportunityid-jobs](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-opportunities-opportunityid-jobs)

---

## Get lead by Id

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/leads/{leadId}`  
**Description:** Get single lead by Id  

**Tags:** `basic` `leads`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `leadId` | template | -... Yes | `string` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**

> Lead

**Sample response:**

```json
{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-leads-leadid](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-leads-leadid)

---

## Get leads

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/leads[?Page][&PageSize][&From][&To][&IncludeBad][&IncludeLost]`  
**Description:** Retrieves leads created within a time range. By default, only New and In Progress leads are returned, but Lost and Bad Leads can be included through query parameters.  

**Tags:** `basic` `leads`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `Page` | query | No | `integer` |  |  |
| `PageSize` | query | No | `integer` |  |  |
| `From` | query | No | `integer` |  | Format: yyyyMMdd, eg. 20240831 |
| `To` | query | No | `integer` |  | Format: yyyyMMdd, eg. 20240831 |
| `IncludeBad` | query | No | `boolean` |  |  |
| `IncludeLost` | query | No | `boolean` |  |  |

### Responses

- **Response: 200 OK**

> Leads

**Sample response:**

```json
{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-leads](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-leads)

---

## Get lost lead/opportunity reasons

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/lost-reasons[?Page][&PageSize]`  
**Description:** Get all of your company's lost lead/opportunity reasons.  

**Tags:** `basic`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `Page` | query | No | `integer` |  |  |
| `PageSize` | query | No | `integer` |  |  |

### Responses

- **Response: 200 OK**

> Lost reasons

**Sample response:**

```json
{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-lost-reasons](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-lost-reasons)

---

## Get move sizes

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/move-sizes[?Page][&PageSize]`  
**Description:** Get all the move sizes that are stored in your company, alongside their description, cubic feet, and weight.  

**Tags:** `basic`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `Page` | query | No | `integer` |  |  |
| `PageSize` | query | No | `integer` |  |  |

### Responses

- **Response: 200 OK**

> Move sizes

**Sample response:**

```json
{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-move-sizes](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-move-sizes)

---

## Get opportunities by customer Id

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/customers/{customerId}/opportunities[?Page][&PageSize]`  
**Description:** Get opportunities by customer Id  

**Tags:** `basic` `opportunities`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `customerId` | template | -... Yes | `string` |  |  |
| `Page` | query | No | `integer` |  |  |
| `PageSize` | query | No | `integer` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**

> Page result of Opportunities

**Sample response:**

```json
[{
    "id": "string",
    "quoteNumber": "string",
    "serviceDate": 0,
    "status": {},
    "createdAtUtc": "string"
}]
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-customers-customerid-opportunities](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-customers-customerid-opportunities)

---

## Get opportunity details

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/opportunities/{opportunityId}[?IncludeTripInfo][&IncludePayments][&IncludeSurveys][&IncludeJobAddresses][&IncludeTasks][&IncludeFiles][&IncludePhotos][&IncludeDocuments][&IncludeCharges][&IncludeDispatchInfo]`  
**Description:** Get detailed information about an opportunity  

**Tags:** `basic` `opportunities`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `opportunityId` | template | -... Yes | `string` |  |  |
| `IncludeTripInfo` | query | No | `boolean` |  |  |
| `IncludePayments` | query | No | `boolean` |  |  |
| `IncludeSurveys` | query | No | `boolean` |  |  |
| `IncludeJobAddresses` | query | No | `boolean` |  | List of job's addresses/stops, returned in the order they were stored going from Origin, to Destination. |
| `IncludeTasks` | query | No | `boolean` |  |  |
| `IncludeFiles` | query | No | `boolean` |  |  |
| `IncludePhotos` | query | No | `boolean` |  |  |
| `IncludeDocuments` | query | No | `boolean` |  |  |
| `IncludeCharges` | query | No | `boolean` |  |  |
| `IncludeDispatchInfo` | query | No | `boolean` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**

> Opportunity details

**Sample response:**

```json
{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-opportunities-opportunityid](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-opportunities-opportunityid)

---

## Get opportunity details by quote number

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/opportunities/quote/{quoteNumber}[?IncludeTripInfo][&IncludePayments][&IncludeSurveys][&IncludeJobAddresses][&IncludeTasks][&IncludeFiles][&IncludePhotos][&IncludeDocuments][&IncludeCharges][&IncludeDispatchInfo]`  
**Description:** Get detailed information about an opportunity  

**Tags:** `basic` `opportunities`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `quoteNumber` | template | -... Yes | `integer` |  |  |
| `IncludeTripInfo` | query | No | `boolean` |  |  |
| `IncludePayments` | query | No | `boolean` |  |  |
| `IncludeSurveys` | query | No | `boolean` |  |  |
| `IncludeJobAddresses` | query | No | `boolean` |  | List of job's addresses/stops, returned in the order they were stored going from Origin, to Destination. |
| `IncludeTasks` | query | No | `boolean` |  |  |
| `IncludeFiles` | query | No | `boolean` |  |  |
| `IncludePhotos` | query | No | `boolean` |  |  |
| `IncludeDocuments` | query | No | `boolean` |  |  |
| `IncludeCharges` | query | No | `boolean` |  |  |
| `IncludeDispatchInfo` | query | No | `boolean` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**

> Opportunity details

**Sample response:**

```json
{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-opportunities-quote-quotenumber](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-opportunities-quote-quotenumber)

---

## Get payments by opportunity Id

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/payments/opportunities/{opportunityId}`  
**Description:** Get opportunity payments by opportunity Id  

**Tags:** `basic` `opportunities`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `opportunityId` | template | -... Yes | `string` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**

> Job

**Sample response:**

```json
[{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-payments-opportunities-opportunityid](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-payments-opportunities-opportunityid)

---

## Get referral sources

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/referral-sources[?Page][&PageSize][&includePrivate][&includeLeadProviders]`  
**Description:** Get all of your account's referral sources, with the option to retrieve all of them or only your public ones (users on public lead forms you might have embedded on your website). If desired, you can also include your active lead providers in the response.  

**Tags:** `basic`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `Page` | query | No | `integer` |  |  |
| `PageSize` | query | No | `integer` |  |  |
| `includePrivate` | query | No | `boolean` |  |  |
| `includeLeadProviders` | query | No | `boolean` |  |  |

### Responses

- **Response: 200 OK**

> Referral sources

**Sample response:**

```json
{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-referral-sources](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-referral-sources)

---

## Get service types

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/service-types[?Page][&PageSize]`  
**Description:** Get all your enabled service types, both system and custom ones.  

**Tags:** `basic`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `Page` | query | No | `integer` |  |  |
| `PageSize` | query | No | `integer` |  |  |

### Responses

- **Response: 200 OK**

> service types

**Sample response:**

```json
{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-service-types](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-service-types)

---

## Get statuses

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/leads/statuses`  
**Description:** Get statuses  

**Tags:** `basic` `leads`

### Request Parameters

_No parameters._

### Responses

- **Response: 200 OK**

> Statuses

**Sample response:**

```json
[{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-leads-statuses](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-leads-statuses)

---

## Get storage accounts by customer Id

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/customers/{customerId}/storage-accounts[?Page][&PageSize]`  
**Description:** Get storage accounts by customer Id  

**Tags:** `basic` `customers`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `customerId` | template | -... Yes | `string` |  |  |
| `Page` | query | No | `integer` |  |  |
| `PageSize` | query | No | `integer` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**

> Storage accounts

**Sample response:**

```json
[{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-customers-customerid-storage-accounts](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-customers-customerid-storage-accounts)

---

## Get tariffs

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/tariffs[?Page][&PageSize][&IncludeDisabled][&IncludeTechMate]`  
**Description:** Get all the tariffs within your company, with the option to include disabled tariffs or not.  

**Tags:** `basic`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `Page` | query | No | `integer` |  |  |
| `PageSize` | query | No | `integer` |  |  |
| `IncludeDisabled` | query | No | `boolean` |  |  |
| `IncludeTechMate` | query | No | `boolean` |  | Include external tariffs created on TechMate in the response. |

### Responses

- **Response: 200 OK**

> Tariffs

**Sample response:**

```json
{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-tariffs](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-tariffs)

---

## Get users

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/users[?Page][&PageSize]`  
**Description:** Get all the office users in your company, with all their key descriptive attributes such as title and role. Crew members are not included.  

**Tags:** `basic`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `Page` | query | No | `integer` |  |  |
| `PageSize` | query | No | `integer` |  |  |

### Responses

- **Response: 200 OK**

> Office users

**Sample response:**

```json
{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-users](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-users)

---
