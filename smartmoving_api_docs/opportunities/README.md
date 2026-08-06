# OPPORTUNITIES - API Endpoints

**Total:** 23 endpoints

---

## Add inventory to an opportunity

**Method:** `POST`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/inventory/rooms/{roomId}[?changeVolumeWeightCalculationMode][&markAsNeedsReview]`  
**Description:** Add items to an existing opportunity: Include the ID if you want to add inventory from your master list, or create a custom inventory through the Name. Each custom inventory created can also be added to the master inventory list if desired.  

**Tags:** `opportunities` `premium`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `opportunityId` | template | -... Yes | `string` |  |  |
| `roomId` | template | -... Yes | `string` |  |  |
| `changeVolumeWeightCalculationMode` | query | No | `boolean` |  | If true or not specified, the opportunity will be updated to calculate by inventory when items are added. |
| `markAsNeedsReview` | query | No | `boolean` |  | If true or not specified, the inventory will be marked as needing review |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**

> Item(s) added to room

**Sample response:**

```json
{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=post-api-premium-opportunities-opportunityid-inventory-rooms-roomid](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=post-api-premium-opportunities-opportunityid-inventory-rooms-roomid)

---

## Add materials to job

**Method:** `POST`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/Estimated/jobs/{jobId}/materials`  
**Description:** Add packing materials to job based on its tariff. When using this endpoint, the materials added will overwrite the materials on the job, if there are any.  

**Tags:** `opportunities` `premium`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `opportunityId` | template | -... Yes | `string` |  |  |
| `jobId` | template | -... Yes | `string` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**

> Materials added to job

**Sample response:**

```json
{
    "materials": [{
        "quantity": 0,
        "materialId": "string"
    }]
}
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=post-api-premium-opportunities-opportunityid-estimated-jobs-jobid-materials](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=post-api-premium-opportunities-opportunityid-estimated-jobs-jobid-materials)

---

## Confirm a job

**Method:** `POST`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/jobs/{jobId}/confirm[?category]`  
**Description:** Confirm a job by jobId and category (optional)  

**Tags:** `opportunities` `premium`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `opportunityId` | template | -... Yes | `string` |  |  |
| `jobId` | template | -... Yes | `string` |  |  |
| `category` | query | No | `string` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**

> OK

**Sample response:**

```json
{opportunityId}
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=post-api-premium-opportunities-opportunityid-jobs-jobid-confirm](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=post-api-premium-opportunities-opportunityid-jobs-jobid-confirm)

---

## Create an opportunity

**Method:** `POST`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/opportunity`  
**Description:** Create an opportunity from scratch, indicating all the required fields. Continue to SmartMoving to get an estimate proposal sent to the customer, or retrieve the estimation from the Get opportunity details endpoint to handle the communication externally.  

**Tags:** `opportunities` `premium`

### Request Parameters

_No parameters._

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**
- **Response: 500 Internal Server Error**

> Opportunity details

**Sample response:**

```json
{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=post-api-premium-opportunity](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=post-api-premium-opportunity)

---

## Create follow-up

**Method:** `POST`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/followups`  
**Description:** Create follow-up for opportunityId  

**Tags:** `opportunities` `premium`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `opportunityId` | template | -... Yes | `string` |  |  |

### Responses

- **Response: 201 Created**
- **Response: 400 Bad Request**

**Sample response:**

```json
{
    "type": {},
    "title": "string",
    "assignedToId": "string",
    "dueDateTime": "string",
    "completedAtUtc": "string",
    "notes": "string",
    "completed": true
}
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=post-api-premium-opportunities-opportunityid-followups](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=post-api-premium-opportunities-opportunityid-followups)

---

## Create job

**Method:** `POST`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/jobs`  
**Description:** Create job for opportunity  

**Tags:** `opportunities` `premium`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `opportunityId` | template | -... Yes | `string` |  |  |

### Responses

- **Response: 201 Created**
- **Response: 404 Not Found**
- **Response: 400 Bad Request**

**Sample response:**

```json
{
    "serviceType": {}
}
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=post-api-premium-opportunities-opportunityid-jobs](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=post-api-premium-opportunities-opportunityid-jobs)

---

## Create rooms

**Method:** `POST`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/rooms`  
**Description:** Add new rooms to your lead or opportunity, and use it to load your job's inventory.  

**Tags:** `opportunities` `premium`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `opportunityId` | template | -... Yes | `string` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**
- **Response: 500 Internal Server Error**

> Room details

**Sample response:**

```json
[{
    "name": "string",
    "roomTypeId": "string"
}]
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=post-api-premium-opportunities-opportunityid-rooms](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=post-api-premium-opportunities-opportunityid-rooms)

---

## Delete follow-up by id

**Method:** `DELETE`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/followups/{followupId}`  
**Description:** Delete single follow-up for opportunityId and follow-up Id  

**Tags:** `opportunities` `premium`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `opportunityId` | template | -... Yes | `string` |  |  |
| `followupId` | template | -... Yes | `string` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**

> OK

**Sample response:**

```json
{opportunityId}
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=delete-api-premium-opportunities-opportunityid-followups-followupid](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=delete-api-premium-opportunities-opportunityid-followups-followupid)

---

## Delete job

**Method:** `DELETE`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/jobs/{jobId}`  
**Description:** Remove job from opportunity  

**Tags:** `opportunities` `premium`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `opportunityId` | template | -... Yes | `string` |  |  |
| `jobId` | template | -... Yes | `string` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 404 Not Found**
- **Response: 400 Bad Request**

> OK

**Sample response:**

```json
{opportunityId}
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=delete-api-premium-opportunities-opportunityid-jobs-jobid](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=delete-api-premium-opportunities-opportunityid-jobs-jobid)

---

## Get documents

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/documents`  
**Description:** Get all (opportunity and job) documents for a given opportunity  

**Tags:** `opportunities` `premium`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `opportunityId` | template | -... Yes | `string` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**

> List of opportunity and job documents

**Sample response:**

```json
{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-premium-opportunities-opportunityid-documents](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-premium-opportunities-opportunityid-documents)

---

## Get follow-up by id

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/followups/{followupId}`  
**Description:** Get single follow-up for opportunityId and follow-up Id  

**Tags:** `opportunities` `premium`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `opportunityId` | template | -... Yes | `string` |  |  |
| `followupId` | template | -... Yes | `string` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**

> Follow-up

**Sample response:**

```json
{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-premium-opportunities-opportunityid-followups-followupid](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-premium-opportunities-opportunityid-followups-followupid)

---

## Get follow-ups

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/followups`  
**Description:** Get all follow-ups for a given opportunity  

**Tags:** `opportunities` `premium`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `opportunityId` | template | -... Yes | `string` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**

> List of follow-ups

**Sample response:**

```json
[{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-premium-opportunities-opportunityid-followups](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-premium-opportunities-opportunityid-followups)

---

## Get job by id

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/jobs/{jobId}[?IncludeEstimatedCharges][&IncludeActualCharges][&IncludeEstimatedMaterials][&IncludeActualMaterials][&IncludeStops][&IncludeDispatchInfo][&IncludeCharges][&IncludeNotes]`  
**Description:** Get job details by Id  

**Tags:** `opportunities` `premium`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `opportunityId` | template | -... Yes | `string` |  |  |
| `jobId` | template | -... Yes | `string` |  |  |
| `IncludeEstimatedCharges` | query | No | `boolean` |  |  |
| `IncludeActualCharges` | query | No | `boolean` |  |  |
| `IncludeEstimatedMaterials` | query | No | `boolean` |  |  |
| `IncludeActualMaterials` | query | No | `boolean` |  |  |
| `IncludeStops` | query | No | `boolean` |  |  |
| `IncludeDispatchInfo` | query | No | `boolean` |  |  |
| `IncludeCharges` | query | No | `boolean` |  |  |
| `IncludeNotes` | query | No | `boolean` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**

> Job

**Sample response:**

```json
{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-premium-opportunities-opportunityid-jobs-jobid](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-premium-opportunities-opportunityid-jobs-jobid)

---

## Get opportunity inventory

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/inventory`  
**Description:** Get detailed information about opportunity inventory  

**Tags:** `opportunities` `premium`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `opportunityId` | template | -... Yes | `string` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**

> Opportunity inventory

**Sample response:**

```json
{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-premium-opportunities-opportunityid-inventory](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-premium-opportunities-opportunityid-inventory)

---

## Get payments by storage account Id

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/payments/storage-accounts/{storageAccountId}`  
**Description:** Get storage payments by storage account Id  

**Tags:** `opportunities` `premium`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `storageAccountId` | template | -... Yes | `string` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**

> Job

**Sample response:**

```json
[{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-premium-payments-storage-accounts-storageaccountid](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-premium-payments-storage-accounts-storageaccountid)

---

## Log calls on an opportunity

**Method:** `POST`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/communication/calls`  
**Description:** Log your calls in your opportunities to ensure your entire team stays updated on the latest events. These will appear as entries on the sales activity page.  

**Tags:** `opportunities` `premium`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `opportunityId` | template | -... Yes | `string` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**
- **Response: 500 Internal Server Error**

> Call added to opportunity

**Sample response:**

```json
{
    "callType": {},
    "outcome": {},
    "callDateTime": "string",
    "description": "string",
    "fromNumber": "string",
    "toNumber": "string",
    "createdBy": "string"
}
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=post-api-premium-opportunities-opportunityid-communication-calls](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=post-api-premium-opportunities-opportunityid-communication-calls)

---

## Log notes in an opportunity

**Method:** `POST`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/communication/notes`  
**Description:** Log notes in your opportunities to ensure your entire team stays updated on the latest events. These will appear as entries on the sales activity page.  

**Tags:** `opportunities` `premium`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `opportunityId` | template | -... Yes | `string` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**
- **Response: 500 Internal Server Error**

> Note added to opportunity

**Sample response:**

```json
{
    "notes": "string",
    "createdBy": "string"
}
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=post-api-premium-opportunities-opportunityid-communication-notes](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=post-api-premium-opportunities-opportunityid-communication-notes)

---

## Mark follow-up completed

**Method:** `POST`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/followups/{followupId}/mark-complete`  
**Description:** Mark an opportunity follow-up as completed  

**Tags:** `opportunities` `premium`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `followupId` | template | -... Yes | `string` |  |  |
| `opportunityId` | template | -... Yes | `string` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**

> Follow-up marked as complete

**Sample response:**

```json
{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=post-api-premium-opportunities-opportunityid-followups-followupid-mark-compl](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=post-api-premium-opportunities-opportunityid-followups-followupid-mark-compl)

---

## Remove opportunity inventory

**Method:** `DELETE`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/inventory/rooms/{roomId}/items/{inventoryItemId}[?changeVolumeWeightCalculationMode][&markAsNeedsReview]`  
**Description:** Remove opportunity inventory  

**Tags:** `opportunities` `premium`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `opportunityId` | template | -... Yes | `string` |  |  |
| `roomId` | template | -... Yes | `string` |  |  |
| `inventoryItemId` | template | -... Yes | `string` |  |  |
| `changeVolumeWeightCalculationMode` | query | No | `boolean` |  | If true or not specified, the opportunity will be updated to calculate by inventory when items are deleted. |
| `markAsNeedsReview` | query | No | `boolean` |  | If true or not specified, the inventory will be marked as needing review |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**

> Item successfully deleted

**Sample response:**

```json
{opportunityId}
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=delete-api-premium-opportunities-opportunityid-inventory-rooms-roomid-items](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=delete-api-premium-opportunities-opportunityid-inventory-rooms-roomid-items)

---

## Request inventory review

**Method:** `POST`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/inventory/submit`  
**Description:** Initiate an inventory review request for a specific opportunity, mirroring the functionality of the "Submit Inventory" button in the Customer Portal. Submissions can be resolved from the opportunity's Sales tab.  

**Tags:** `opportunities` `premium`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `opportunityId` | template | -... Yes | `string` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**

> Inventory submitted successfully

**Sample response:**

```json
{opportunityId}
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=post-api-premium-opportunities-opportunityid-inventory-submit](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=post-api-premium-opportunities-opportunityid-inventory-submit)

---

## Update follow-up

**Method:** `PUT`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/followups/{followupId}`  
**Description:** Update single follow-up for opportunityId and follow-up Id  

**Tags:** `opportunities` `premium`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `opportunityId` | template | -... Yes | `string` |  |  |
| `followupId` | template | -... Yes | `string` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**

> OK

**Sample response:**

```json
{
    "type": {},
    "title": "string",
    "assignedToId": "string",
    "dueDateTime": "string",
    "completedAtUtc": "string",
    "notes": "string",
    "completed": true
}
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=put-api-premium-opportunities-opportunityid-followups-followupid](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=put-api-premium-opportunities-opportunityid-followups-followupid)

---

## Update opportunity inventory

**Method:** `PUT`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/inventory/rooms/{roomId}/items/{inventoryItemId}[?changeVolumeWeightCalculationMode][&markAsNeedsReview]`  
**Description:** Update opportunity inventory  

**Tags:** `opportunities` `premium`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `opportunityId` | template | -... Yes | `string` |  |  |
| `roomId` | template | -... Yes | `string` |  |  |
| `inventoryItemId` | template | -... Yes | `string` |  |  |
| `changeVolumeWeightCalculationMode` | query | No | `boolean` |  | If true or not specified, the opportunity will be updated to calculate by inventory when items are updated. |
| `markAsNeedsReview` | query | No | `boolean` |  | If true or not specified, the inventory will be marked as needing review |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**

> Item successfully updated

**Sample response:**

```json
{
    "notes": "string",
    "volume": 0,
    "weight": 0,
    "quantity": 0,
    "quantityNotGoing": 0
}
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=put-api-premium-opportunities-opportunityid-inventory-rooms-roomid-items-inv](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=put-api-premium-opportunities-opportunityid-inventory-rooms-roomid-items-inv)

---

## Update opportunity properties

**Method:** `PATCH`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}`  
**Description:** Update specific properties of an opportunity. Only updates properties that are provided in the request.  

**Tags:** `opportunities` `premium`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `opportunityId` | template | -... Yes | `string` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**
- **Response: 500 Internal Server Error**

> Opportunity updated successfully

**Sample response:**

```json
{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=patch-api-premium-opportunities-opportunityid](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=patch-api-premium-opportunities-opportunityid)

---
