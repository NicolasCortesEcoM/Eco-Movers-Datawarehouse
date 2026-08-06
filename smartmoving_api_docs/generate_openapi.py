import json
import re
import urllib.parse

def load_json(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        return json.load(f)

def clean_path(path, base_url, doc_url):
    if not path:
        # Extract from doc_url
        # e.g., https://developer.smartmoving.com/api-details#api=public-api-v1&operation=post-api-premium-opportunities-opportunityid-attachments
        parsed = urllib.parse.urlparse(doc_url)
        fragment = parsed.fragment
        params = urllib.parse.parse_qs(fragment)
        operation = params.get('operation', [''])[0]
        if operation:
            # e.g., post-api-premium-opportunities-opportunityid-attachments
            # We can't easily reconstruct the exact path with {} from just this, but we can try to make a best effort
            # Actually, let's look at the operation string. It usually starts with method-api-...
            parts = operation.split('-')
            if len(parts) > 1:
                # remove method
                path_parts = parts[1:]
                # We can try to guess parameters, but it's hard. 
                # Let's just create a path like /api/premium/opportunities/{opportunityId}/attachments
                # We will just replace known parameter names if possible, but for now let's just join them.
                # A better way: just use the parts
                reconstructed = "/" + "/".join(path_parts)
                # We will fix parameters later if needed.
                return reconstructed
        return "Not Found"
    
    # Remove base_url
    if path.startswith(base_url):
        path = path[len(base_url):]
    
    # Remove query parameter brackets like [?Page][&PageSize]
    path = re.sub(r'\[\?[^\]]+\]', '', path)
    path = re.sub(r'\[\&[^\]]+\]', '', path)
    
    if not path.startswith('/'):
        path = '/' + path
        
    return path

def parse_schema_sample(sample):
    if not sample:
        return None
    try:
        # Sometimes sample is a string containing JSON
        if isinstance(sample, str):
            # Fix truncated JSON like "{\n    \"base64Contents\": \"string\",\n    \"fileName\": \"string\",\n    \"category\": {}"
            # It's hard to fix arbitrary truncated JSON. Let's try to parse, if fails, return as string example.
            try:
                parsed = json.loads(sample)
                return parsed
            except json.JSONDecodeError:
                # Try to add closing brace
                try:
                    parsed = json.loads(sample + "}")
                    return parsed
                except:
                    return sample
        return sample
    except:
        return sample

def build_openapi():
    index_data = load_json('index.json')
    endpoints_data = load_json('all_endpoints.json')
    
    base_url = index_data.get('base_url', 'https://api-public.smartmoving.com/v1')
    
    openapi = {
        "openapi": "3.0.3",
        "info": {
            "title": index_data.get('api_name', 'SmartMoving External API'),
            "version": index_data.get('version', 'v1'),
            "description": "SmartMoving API OpenAPI Specification generated from documentation."
        },
        "servers": [
            {
                "url": base_url
            }
        ],
        "paths": {},
        "components": {
            "securitySchemes": {
                "ApiKeyAuth": {
                    "type": "apiKey",
                    "in": "header",
                    "name": "x-api-key"
                }
            }
        },
        "security": [
            {
                "ApiKeyAuth": []
            }
        ]
    }
    
    for ep in endpoints_data.get('endpoints', []):
        method = ep.get('method', '').lower()
        if not method:
            continue
            
        raw_path = ep.get('path', '')
        doc_url = ep.get('doc_url', '')
        path = clean_path(raw_path, base_url, doc_url)
        
        if path == "Not Found":
            path = "/unknown-path-" + ep.get('title', '').replace(' ', '-').lower()
            
        if path not in openapi['paths']:
            openapi['paths'][path] = {}
            
        operation_id = ep.get('title', '').replace(' ', '_').replace('/', '_').replace('-', '_').lower()
        operation_id = re.sub(r'[^a-z0-9_]', '', operation_id)
        
        description = ep.get('description')
        if not description:
            description = "Not Found"
            
        op = {
            "summary": ep.get('title', 'Not Found'),
            "description": description,
            "operationId": operation_id,
            "tags": ep.get('tags', []),
            "parameters": [],
            "responses": {}
        }
        
        # Parameters
        for param in ep.get('parameters', []):
            param_in = param.get('location', 'query')
            if param_in == 'template':
                param_in = 'path'
                
            p = {
                "name": param.get('name', 'unknown'),
                "in": param_in,
                "required": param.get('required', False),
                "schema": {
                    "type": param.get('type_', 'string')
                }
            }
            if param.get('description'):
                p["description"] = param.get('description')
            op["parameters"].append(p)
            
        # Payload mapping
        schema_sample = parse_schema_sample(ep.get('response_schema_sample'))
        
        if method in ['post', 'put', 'patch']:
            if schema_sample:
                op["requestBody"] = {
                    "content": {
                        "application/json": {
                            "example": schema_sample
                        }
                    }
                }
            # Default response for mutations
            op["responses"]["200"] = {
                "description": ep.get('response_description') or "Success"
            }
        else:
            # GET, DELETE, etc.
            resp_content = {}
            if schema_sample:
                resp_content = {
                    "application/json": {
                        "example": schema_sample
                    }
                }
            op["responses"]["200"] = {
                "description": ep.get('response_description') or "Success"
            }
            if resp_content:
                op["responses"]["200"]["content"] = resp_content
                
        # Add other response codes
        for code_str in ep.get('response_codes', []):
            # e.g., "Response: 400 Bad Request"
            match = re.search(r'(\d{3})', code_str)
            if match:
                code = match.group(1)
                if code != "200":
                    op["responses"][code] = {
                        "description": code_str.replace(f"Response: {code} ", "")
                    }
                    
        openapi['paths'][path][method] = op

    return openapi

if __name__ == "__main__":
    openapi_obj = build_openapi()
    
    try:
        import yaml
        with open('openapi.yaml', 'w', encoding='utf-8') as f:
            yaml.dump(openapi_obj, f, sort_keys=False, allow_unicode=True)
        print("Successfully wrote openapi.yaml using PyYAML")
    except ImportError:
        print("PyYAML not installed, writing to openapi.json first...")
        with open('openapi.json', 'w', encoding='utf-8') as f:
            json.dump(openapi_obj, f, indent=2)
        print("Wrote openapi.json. Please install pyyaml to generate yaml.")
