# GENERAL - API Endpoints

**Total:** 2 endpoints

---

## /api/ping - GET

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/ping`  
**Tags:** `ping`

### Request Parameters

_No parameters._

### Responses

- **Response: 200 OK**

> OK

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-ping](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-ping)

---

## Add attachment to opportunity

**Method:** `POST`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/opportunities/{opportunityId}/attachments`  
**Description:** Attaches a file to an opportunity. File must be of type '.doc', '.docx', '.xls', '.xlsx', '.pdf', '.txt', '.csv', '.png', '.jpeg', or '.jpg'. The
                       file content must be a Base64 encoded byte array. The documents category does not accept image files.  

**Tags:** `opportunities` `premium`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `opportunityId` | template | -... Yes | `string` |  |  |

### Responses

- **Response: 201 Created**
- **Response: 400 Bad Request**

> File attached to opportunity

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=post-api-premium-opportunities-opportunityid-attachments](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=post-api-premium-opportunities-opportunityid-attachments)

---
