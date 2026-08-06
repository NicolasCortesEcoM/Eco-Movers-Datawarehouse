Webhooks
SmartMoving Webhooks
Overview
SmartMoving webhooks notify external tools as soon as an event occurs, such as:

A job being booked
A payment being recorded
A customer being created
An opportunity being updated
A follow-up being created or completed

Instead of checking SmartMoving manually for updates, SmartMoving sends event data automatically to a webhook URL that you provide.
Webhooks are useful for keeping external systems synchronized in real time, including:

CRM platforms
Accounting software
Dispatch tools
Internal automation systems
Applications built on top of the SmartMoving API

API keys and webhooks can be managed in the SmartMoving integrations settings.

Event Payload Conventions
Webhook payloads are sent as JSON objects.
Most payloads contain:

event-type: The webhook event identifier.
A resource ID such as opportunity-id, job-id, customer-id, payment-id, or followup-id.
Additional resource-specific information when applicable.

Events
Opportunity Events
opportunity-created
Fired when a new opportunity is added to SmartMoving. The opportunity may be submitted through a web form, entered manually, or created through an integration or API.
json{
"event-type": "opportunity-created",
"opportunity-id": "88393124-4ca1-4a8d-8529-05d75b7bf991",
"opportunity-status": 1
}
opportunity-status-changed
Fired when an opportunity's status is updated.
json{
"event-type": "opportunity-status-changed",
"opportunity-id": "03efcb5e-2bde-4cc8-a22f-60514334cc59",
"opportunity-status": 1
}
opportunity-changed
Fired when any field on an existing opportunity is modified.
Examples include:

Move date
Opportunity status
Origin or destination
Contact details
Move size

json{
"event-type": "opportunity-changed",
"opportunity-id": "a2da9c4b-0840-4f64-a375-035cdedd3af0",
"opportunity-status": 1
}
opportunity-deleted
Fired when an opportunity is permanently removed from SmartMoving.
json{
"event-type": "opportunity-deleted",
"opportunity-id": "9fda1b4d-89f6-4f8d-9dc2-cba035aa02d5"
}

Follow-Up Events
follow-up-created
Fired when a follow-up task is created for an opportunity.
json{
"event-type": "follow-up-created",
"followup-id": "282858b0-85ff-4165-8b44-24a92c2cac72",
"opportunity-id": "c12850fa-9320-412a-91e2-969a4932559b"
}
follow-up-completed
Fired when a follow-up task is marked as complete.
json{
"event-type": "follow-up-completed",
"followup-id": "f09a88ce-962a-45fb-b358-2fdf6debc79d",
"opportunity-id": "01346450-212c-431f-b5b5-79958fec4746"
}
follow-up-changed
Fired when a follow-up task is modified.
json{
"event-type": "follow-up-changed",
"followup-id": "e1aee908-8b84-41af-80d5-2dd3089f2460"
}
follow-up-deleted
Fired when a follow-up task is removed.
json{
"event-type": "follow-up-deleted",
"followup-id": "21e61035-ad74-4e0b-ac22-1b6ca2eedc35"
}

Payment Events
payment-made
Fired when a payment is recorded on a job.
The payment may be:

A deposit
A partial payment
A final balance

The event may also include:

opportunity-id when the payment belongs to an opportunity
storage-id when the payment belongs to storage

json{
"event-type": "payment-made",
"payment-id": "8c0d6a55-e3d6-4bac-b815-88e339339257"
}

Customer Events
customer-created
Fired when a new customer record is created in SmartMoving.
json{
"event-type": "customer-created",
"customer-id": "2912f77b-878d-4c97-befa-2b7776d441f3"
}
customer-updated
Fired when an existing customer's information is modified.
Examples include:

Name
Email address
Phone number
Address

json{
"event-type": "customer-updated",
"customer-id": "90ba1822-56cb-4360-8bb3-e19958a1bf98"
}

Job Events
job-created
Fired when a new job is created in SmartMoving.
json{
"event-type": "job-created",
"job-id": "b63a338a-dbc5-455c-912f-ef7f82b4ef14"
}
job-deleted
Fired when a job is permanently deleted from SmartMoving.
json{
"event-type": "job-deleted",
"job-id": "79b120b8-842c-47af-89d1-5f6d70de2a05"
}
job-finalized
Fired when a job is finalized. Finalization indicates that all services and charges have been confirmed and billing is locked.
json{
"event-type": "job-finalized",
"job-id": "64260040-8967-4753-97e4-57eb8ce6a6fc"
}
job-closed
Fired when a job is marked as closed after completion.
json{
"event-type": "job-closed",
"job-id": "5c911205-f86e-4724-928d-94394d66523c"
}
job-reset
Fired when a job is reset from a finalized or closed state back to an editable status.
json{
"event-type": "job-reset",
"job-id": "75808823-354b-429c-abc7-7b10ee5c5edb"
}
service-type-changed
Fired when the service type assigned to a job is updated.
json{
"event-type": "service-type-changed",
"job-id": "14ebfb8a-b632-4da3-9b69-60b89c1c32aa"
}

Event Summary
Event TypeResourceDescriptionopportunity-createdOpportunityA new opportunity was created.opportunity-status-changedOpportunityAn opportunity's status changed.opportunity-changedOpportunityOne or more opportunity fields changed.opportunity-deletedOpportunityAn opportunity was permanently deleted.follow-up-createdFollow-upA follow-up task was created.follow-up-completedFollow-upA follow-up task was completed.follow-up-changedFollow-upA follow-up task was modified.follow-up-deletedFollow-upA follow-up task was deleted.payment-madePaymentA payment was recorded.customer-createdCustomerA customer record was created.customer-updatedCustomerA customer record was updated.job-createdJobA new job was created.job-deletedJobA job was permanently deleted.job-finalizedJobA job was finalized and billing was locked.job-closedJobA completed job was closed.job-resetJobA finalized or closed job was made editable again.service-type-changedJobA job's service type changed.

Recommended Webhook Processing Flow
A webhook receiver should generally:

Accept the incoming HTTP request.
Parse the JSON payload.
Read the event-type field.
Validate the required resource identifier.
Retrieve additional information from the SmartMoving API when needed.
Process the event idempotently to avoid duplicate actions.
Return a successful HTTP response promptly.
Log the event and any processing errors.

Example event-routing pseudocode:
textreceive webhook payload

event_type = payload["event-type"]

switch event_type:
case "opportunity-created":
process new opportunity

    case "payment-made":
        process payment

    case "customer-updated":
        synchronize customer

    case "job-finalized":
        lock downstream billing data

    default:
        log unsupported event

Notes for AI Systems
When interpreting these webhook payloads:

Treat event-type as the primary event discriminator.
Treat UUID values as opaque resource identifiers.
Do not assume the webhook contains the complete resource record.
Use the relevant SmartMoving API endpoint to retrieve full resource details when necessary.
A receiver should handle duplicate deliveries safely.
Unknown event types should be logged rather than causing the entire webhook endpoint to fail.
