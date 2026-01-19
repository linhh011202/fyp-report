# Payment System (PR #10)

Tài liệu về hệ thống payment với Plan, Subscription, và Stripe integration.

## Architecture Overview

```mermaid
flowchart TB
    subgraph "Client"
        WEB[Web App]
        MOBILE[Mobile App]
    end

    subgraph "API Gateway"
        subgraph "Plan Module"
            PLAN_CTRL[PlanController]
            PLAN_SVC[PlanService]
        end

        subgraph "Subscription Module"
            SUB_CTRL[SubscriptionController]
            SUB_SVC[SubscriptionService]
        end

        subgraph "Stripe Module"
            STRIPE_CTRL[StripeController]
            STRIPE_SVC[StripeService]
        end
    end

    subgraph "External"
        STRIPE[Stripe API]
    end

    subgraph "Storage"
        MONGO[(MongoDB)]
        REDIS[(Redis)]
    end

    WEB --> STRIPE_CTRL
    MOBILE --> STRIPE_CTRL
    
    STRIPE_CTRL --> STRIPE_SVC
    STRIPE_CTRL --> PLAN_SVC
    STRIPE_CTRL --> SUB_SVC
    
    STRIPE_SVC --> STRIPE
    STRIPE_SVC --> REDIS
    
    PLAN_SVC --> REDIS
    PLAN_SVC --> MONGO
    
    SUB_SVC --> MONGO
    
    STRIPE -->|Webhook| STRIPE_CTRL
```

---

## Modules

| Module | Description | Documentation |
|--------|-------------|---------------|
| **Plan** | Pricing plans với versioning và Redis caching | [plan.md](./plan.md) |
| **Subscription** | User subscription với quota tracking | [subscription.md](./subscription.md) |
| **Stripe** | Payment processing và webhook handling | [stripe.md](./stripe.md) |

---

## Database Schema

```mermaid
erDiagram
    Users ||--|| Subscriptions : has
    Plans ||--o{ Subscriptions : "priceId links to"
    
    Plans {
        ObjectId _id PK
        String id UK
        String plans "JSON"
        Number version UK
        Date createdAt
    }
    
    Subscriptions {
        ObjectId _id PK
        ObjectId user FK
        String stripeSubscriptionId
        String stripeCustomerId
        String status
        Object quota
        Object usage
        Date startDate
        Date endDate
    }
```

---

## API Endpoints

### Plan APIs

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `POST` | `/plans` | Admin | Create new plan version |
| `GET` | `/plans/latest` | Public | Get latest plans (cached) |

### Subscription APIs

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `GET` | `/subscriptions/user/:id` | User/Admin | Get subscription |
| `PUT` | `/subscriptions/user/:id` | Admin | Update subscription |

### Stripe APIs

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `POST` | `/stripe/stripe-checkout-session` | User | Create checkout session |
| `POST` | `/stripe/webhook` | Stripe | Handle webhooks |
| `POST` | `/stripe/check-subscription-status` | User | Check sub status |
| `POST` | `/stripe/cancel-subscription` | User | Cancel subscription |
| `POST` | `/stripe/resume-subscription` | User | Resume subscription |
| `POST` | `/stripe/get-price` | Public | Get price info (cached) |

---

## Payment Flow

```mermaid
sequenceDiagram
    participant User
    participant Frontend
    participant API as API Gateway
    participant Stripe
    participant DB as MongoDB

    User->>Frontend: Select plan
    Frontend->>API: POST /stripe/stripe-checkout-session
    API->>Stripe: Create checkout session
    Stripe-->>API: {url, sessionId}
    API-->>Frontend: Checkout URL
    
    Frontend->>Stripe: Redirect to checkout.stripe.com
    User->>Stripe: Complete payment
    Stripe->>User: Redirect to success URL
    
    Stripe->>API: POST /stripe/webhook<br/>checkout.session.completed
    API->>API: Get priceId from session
    API->>API: Match plan by priceId
    API->>DB: Create/Update subscription
    
    User->>Frontend: Use service
    Frontend->>API: API request
    API->>API: checkSubscription()
    API-->>Frontend: Success / Quota exceeded
```

---

## Redis Caching

| Key Pattern | TTL | Purpose |
|-------------|-----|---------|
| `plan:latest` | 1 hour | Cache latest plan version |
| `stripe:price:xxx` | 24 hours | Cache Stripe price info |

### Cache Invalidation

| Event | Action |
|-------|--------|
| New plan created | Delete `plan:latest` |
| Price not found | Cache `NULL` for 60s |

---

## Configuration

```bash
# Stripe
STRIPE_SECRET_KEY=sk_xxx
STRIPE_WEBHOOK_SECRET=whsec_xxx
STRIPE_SUCCESS_URL=https://app.example.com/success
STRIPE_CANCEL_URL=https://app.example.com/cancel

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=secret
```

---

## Files Changed (PR #10)

```
src/modules/plan/
├── plan.module.ts
├── plan.controller.ts
├── plan.service.ts      # Redis caching
├── plan.schema.ts
└── plan.dto.ts

src/modules/subscription/
├── subscription.module.ts
├── subscription.controller.ts
├── subscription.service.ts
├── subscription.schema.ts  # quota, usage, stripeIds
└── subscription.dto.ts

src/modules/stripe/
├── stripe.module.ts
├── stripe.controller.ts    # Webhook, cancel, resume
├── stripe.service.ts       # Redis caching
└── stripe.dto.ts
```
