# PREMIUM - API Endpoints

**Total:** 3 endpoints

---

## Get master inventory list

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/inventory[?Page][&PageSize]`  
**Description:** Get the master inventory list with all the relevant information, and use its IDs to add inventory items.  

**Tags:** `premium`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `Page` | query | No | `integer` |  |  |
| `PageSize` | query | No | `integer` |  |  |

### Responses

- **Response: 200 OK**

> Inventory

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
        "shortCode": 0,
        "volume": 0,
        "weight": 0
    }]
}
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-premium-inventory](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-premium-inventory)

---

## Get materials by tariff id

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/tariffs/{tariffId}/materials[?Page][&PageSize]`  
**Description:** Get all your tariff's packing materials information.  

**Tags:** `premium`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `tariffId` | template | -... Yes | `string` |  |  |
| `Page` | query | No | `integer` |  |  |
| `PageSize` | query | No | `integer` |  |  |

### Responses

- **Response: 200 OK**
- **Response: 400 Bad Request**

> Tariff materials

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
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-premium-tariffs-tariffid-materials](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-premium-tariffs-tariffid-materials)

---

## Get room types

**Method:** `GET`  
**Path:** `https://api-public.smartmoving.com/v1/api/premium/room-types[?Page][&PageSize]`  
**Description:** Get all the room types that are stored in your company's inventory configuration.  

**Tags:** `premium`

### Request Parameters

| Name | In | Required | Type | Example | Description |
|------|----|----------|------|---------|-------------|
| `Page` | query | No | `integer` |  |  |
| `PageSize` | query | No | `integer` |  |  |

### Responses

- **Response: 200 OK**

> Room Types

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
        "name": "string"
    }]
}
```

**Documentation:** [https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-premium-room-types](https://developer.smartmoving.com/api-details#api=public-api-v1&operation=get-api-premium-room-types)

---
