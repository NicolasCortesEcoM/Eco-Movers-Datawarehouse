# LEADS - API Endpoints

**Total:** 5 endpoints

---

## Convert lead to opportunity

**Method:** `PUT`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/lead/{id}/convert`  
**Description:** Convert lead to opportunity  

**Tags:** `leads` `premium`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `id` | template | -... Yes | `string` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**
- **Response: 500 Internal Server Error**

> Opportunity details

**Sample response:**

```json
{
    "opportunityId": "string"
}
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=put-api-premium-lead-id-convert](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=put-api-premium-lead-id-convert)

---

## Create a lead

**Method:** `POST`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/leads`  
**Description:** Submit a new lead to SmartMoving through the Premium API. Either ReferralSource or ReferralSourceId is required. For names, provide at least one of FullName, FirstName, or LastName.  

**Tags:** `leads` `premium`

### Request Parameters

_No parameters._

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**
- **Response: 500 Internal Server Error**

> Lead created successfully

**Sample response:**

```json
{
    "leadId": "string"
}
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=post-api-premium-leads](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=post-api-premium-leads)

---

## Get leads by sales person Id

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/leads/sales/{salesPersonId}[?Page][&PageSize]`  
**Description:** Get leads by sales person Id  

**Tags:** `leads` `premium`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `salesPersonId` | template | -... Yes | `string` |  |  |
| `Page` | query | No | `integer` |  |  |
| `PageSize` | query | No | `integer` |  |  |

### Optional / Filter Parameters

- **`Page`** / **`PageSize`** — standard pagination; omit for page 1 with the default page size.

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
        "badLeadReason": "string",
        "moveSizeName": "string",
        "createdAtUtc": "string"
    }]
}
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-premium-leads-sales-salespersonid](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-premium-leads-sales-salespersonid)

---

## Partially update lead

**Method:** `PATCH`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/leads/{leadId}`  
**Description:** Partially update a lead by its ID with only the fields you want to change  

**Tags:** `leads` `premium`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `leadId` | template | -... Yes | `string` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 500 Internal Server Error**

> Lead updated

**Sample response:**

```json
{
    "leadId": "string"
}
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=patch-api-premium-leads-leadid](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=patch-api-premium-leads-leadid)

---

## Update lead

**Method:** `PUT`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/leads/{leadId}`  
**Description:** Update a lead by its ID and easily modify its details  

**Tags:** `leads` `premium`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `leadId` | template | -... Yes | `string` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 500 Internal Server Error**

> Lead updated

**Sample response:**

```json
{
    "leadId": "string"
}
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=put-api-premium-leads-leadid](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=put-api-premium-leads-leadid)

---
