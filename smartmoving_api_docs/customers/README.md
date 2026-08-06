# CUSTOMERS - API Endpoints

**Total:** 4 endpoints

---

## Create a customer

**Method:** `POST`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/customers`  
**Description:** Create a customer  

**Tags:** `customers` `premium`

### Request Parameters

_No parameters._

### Responses

- **Response: 200 OK**

> Customer Id

**Sample response:**

```json
{
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

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=post-api-premium-customers](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=post-api-premium-customers)

---

## Get service tickets by customer Id

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/customers/{customerId}/service-tickets[?Page][&PageSize]`  
**Description:** Get service tickets by customer Id  

**Tags:** `customers`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `customerId` | template | -... Yes | `string` |  |  |
| `Page` | query | No | `integer` |  |  |
| `PageSize` | query | No | `integer` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**

> Service tickets

**Sample response:**

```json
[{
    "id": "string",
    "jobId": "string",
    "name": "string",
    "type": {},
    "status": {},
    "priority": {},
    "createdAtUtc": "string"
}]
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-premium-customers-customerid-service-tickets](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-premium-customers-customerid-service-tickets)

---

## Search customers by name, email address or phone number

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/customers/search[?searchQuery]`  
**Description:** Search customers by name, email address or phone number  

**Tags:** `customers` `premium`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `searchQuery` | query | No | `string` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**

> Matching customers

**Sample response:**

```json
[{
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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-premium-customers-search](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-premium-customers-search)

---

## Update a customer

**Method:** `PUT`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/customers/{customerId}`  
**Description:** Update a customer  

**Tags:** `customers` `premium`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `customerId` | template | -... Yes | `string` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**

> Success

**Sample response:**

```json
{
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

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=put-api-premium-customers-customerid](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=put-api-premium-customers-customerid)

---
