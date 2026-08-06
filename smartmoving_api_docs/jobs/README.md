# JOBS - API Endpoints

**Total:** 2 endpoints

---

## Update job notes

**Method:** `PATCH`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/jobs/{jobId}/notes`  
**Description:** Update any of the note properties on a job such as CrewNotes, CustomerNotes, InternalNotes, AccountingNotes, or DispatcherNotes  

**Tags:** `jobs` `premium`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `opportunityId` | template | -... Yes | `string` |  |  |
| `jobId` | template | -... Yes | `string` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 404 Not Found**
- **Response: 500 Internal Server Error**

> Notes updated successfully

**Sample response:**

```json
{
    "crewNotes": "string",
    "customerNotes": "string",
    "internalNotes": "string",
    "accountingNotes": "string",
    "dispatcherNotes": "string"
}
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=patch-api-premium-opportunities-opportunityid-jobs-jobid-notes](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=patch-api-premium-opportunities-opportunityid-jobs-jobid-notes)

---

## Update job stops

**Method:** `PUT`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/jobs/{jobId}/stops`  
**Description:** Update all stops for a job  

**Tags:** `jobs` `opportunities` `premium`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `opportunityId` | template | -... Yes | `string` |  |  |
| `jobId` | template | -... Yes | `string` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**
- **Response: 404 Not Found**

> Updated stops

**Sample response:**

```json
[{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=put-api-premium-opportunities-opportunityid-jobs-jobid-stops](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=put-api-premium-opportunities-opportunityid-jobs-jobid-stops)

---
