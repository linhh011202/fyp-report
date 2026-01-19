# Subscription & Payment System

## Tổng Quan

Hệ thống payment sử dụng **Stripe** để xử lý subscriptions. Các tính năng chính:
- Hiển thị plans với giá từ Stripe
- Checkout flow với Stripe Checkout
- Cancel/Resume subscriptions
- Subscription status tracking

---

## 1. System Architecture

```mermaid
graph TB
    subgraph "Frontend Components"
        A[Subscription.vue]
        B[PlanCard.vue]
        C[Success.vue]
        D[Cancel.vue]
    end
    
    subgraph "Services"
        E[stripeService]
        F[plansService]
        G[userService]
    end
    
    subgraph "Backend Endpoints"
        H["/stripe/stripe-checkout-session"]
        I["/stripe/check-subscription-status"]
        J["/stripe/cancel-subscription"]
        K["/stripe/resume-subscription"]
        L["/stripe/get-price"]
        M["/plans/latest"]
        N["/subscriptions/user/:id"]
    end
    
    subgraph "Stripe Cloud"
        O[Stripe Checkout]
        P[Stripe Prices API]
        Q[Stripe Subscriptions]
    end
    
    A --> E
    A --> F
    A --> G
    B --> E
    
    E --> H --> O
    E --> I --> Q
    E --> J --> Q
    E --> K --> Q
    E --> L --> P
    F --> M
    G --> N
```

---

## 2. Stripe Service

### 2.1 Class Diagram

```mermaid
classDiagram
    class StripeService {
        +createCheckoutSession(priceId) Promise~CheckoutSession~
        +checkSubscriptionStatus(subscriptionId) Promise~Status~
        +cancelSubscription(subscriptionId) Promise~Result~
        +resumeSubscription(subscriptionId) Promise~Status~
        +getPriceInfo(priceId) Promise~PriceInfo~
        -handleApiError(error)
    }
    
    class CheckoutSession {
        url: string
        sessionId: string
    }
    
    class PriceInfo {
        currency: string
        unit_amount: number
        unit_amount_decimal: string
        recurring: RecurringInfo
    }
    
    class RecurringInfo {
        interval: string
        interval_count: number
    }
    
    class SubscriptionStatus {
        status: string
        isCancelled: boolean
        currentPeriodEnd: number
        cancellationDetails: object
    }
    
    StripeService --> CheckoutSession
    StripeService --> PriceInfo
    StripeService --> SubscriptionStatus
    PriceInfo --> RecurringInfo
```

### 2.2 Methods Detail

| Method | HTTP | Endpoint | Auth | Description |
|--------|------|----------|------|-------------|
| `createCheckoutSession` | POST | `/stripe/stripe-checkout-session` | ✅ | Tạo Stripe Checkout session |
| `checkSubscriptionStatus` | POST | `/stripe/check-subscription-status` | ✅ | Kiểm tra trạng thái subscription |
| `cancelSubscription` | POST | `/stripe/cancel-subscription` | ✅ | Hủy subscription (at period end) |
| `resumeSubscription` | POST | `/stripe/resume-subscription` | ✅ | Resume subscription đã hủy |
| `getPriceInfo` | POST | `/stripe/get-price` | ❌ | Lấy thông tin giá từ Stripe |

---

## 3. Subscription Purchase Flow

### 3.1 Complete Flow

```mermaid
sequenceDiagram
    participant U as User
    participant SUB as Subscription.vue
    participant PC as PlanCard.vue
    participant SS as StripeService
    participant PS as PlansService
    participant BE as Backend
    participant ST as Stripe
    
    Note over U, ST: 1. Load Plans
    U->>SUB: Visit /subscription
    SUB->>PS: getLatestPlans()
    PS->>BE: GET /plans/latest
    BE-->>PS: { plans[], version }
    PS-->>SUB: plans[]
    SUB->>PC: Render PlanCards
    
    Note over U, ST: 2. Load Prices
    loop Each PlanCard
        PC->>SS: getPriceInfo(plan.priceId)
        SS->>BE: POST /stripe/get-price
        BE->>ST: Retrieve Price
        ST-->>BE: Price Info
        BE-->>SS: { currency, unit_amount, recurring }
        SS-->>PC: Display formatted price
    end
    
    Note over U, ST: 3. Checkout
    U->>PC: Click "Subscribe Now"
    PC->>SUB: emit('subscribe', priceId)
    SUB->>SS: createCheckoutSession(priceId)
    SS->>BE: POST /stripe/stripe-checkout-session
    BE->>ST: Create Checkout Session
    ST-->>BE: { url, sessionId }
    BE-->>SS: Redirect URL
    SS-->>SUB: URL
    SUB->>ST: window.location.href = url
    
    Note over U, ST: 4. Payment on Stripe
    ST->>ST: User enters payment details
    ST->>ST: Process payment
    
    alt Payment Success
        ST-->>SUB: Redirect to /success
    else Payment Failed/Cancelled
        ST-->>SUB: Redirect to /cancel
    end
```

### 3.2 Price Display Logic

```javascript
// PlanCard.vue
computed: {
  formattedPrice() {
    if (!this.priceInfo) return 'N/A'
    
    // Convert from cents to dollar
    const amount = this.priceInfo.unit_amount_decimal
      ? (parseInt(this.priceInfo.unit_amount_decimal) / 100).toFixed(2)
      : (this.priceInfo.unit_amount / 100).toFixed(2)
    
    const currency = this.priceInfo.currency.toUpperCase()
    return `${currency} $${amount}`
  },
  
  billingInterval() {
    if (!this.priceInfo?.recurring) return 'one-time'
    return this.priceInfo.recurring.interval // 'month' or 'year'
  }
}
```

---

## 4. Subscription Status Management

### 4.1 State Diagram

```mermaid
stateDiagram-v2
    [*] --> NoSubscription
    
    NoSubscription --> Active: User purchases plan
    Active --> ScheduledCancel: User cancels
    ScheduledCancel --> Active: User resumes
    ScheduledCancel --> Expired: Period ends
    Active --> Expired: Period ends without renewal
    
    state Active {
        [*] --> Checking
        Checking --> Valid: Status OK
        Valid --> Checking: Every page load
    }
    
    state ScheduledCancel {
        [*] --> AccessGranted
        AccessGranted --> AccessDenied: currentPeriodEnd reached
    }
    
    Expired --> NoSubscription: Show plans again
```

### 4.2 Status Check Flow

```mermaid
sequenceDiagram
    participant SUB as Subscription.vue
    participant US as UserService
    participant SS as StripeService
    participant BE as Backend
    participant ST as Stripe
    
    SUB->>US: getCurrentUser()
    US-->>SUB: { _id, ... }
    
    SUB->>US: getUserSubscription(userId)
    US->>BE: GET /subscriptions/user/:id
    BE-->>US: Subscription object
    US-->>SUB: subscription
    
    SUB->>SUB: Check if subscription.status === 'active'
    SUB->>SUB: Check if endDate > now
    
    alt Has Active Subscription
        SUB->>SS: checkSubscriptionStatus(stripeSubscriptionId)
        SS->>BE: POST /stripe/check-subscription-status
        BE->>ST: Retrieve Subscription
        ST-->>BE: Subscription details
        BE-->>SS: { status, isCancelled, currentPeriodEnd }
        SS-->>SUB: Update subscriptionStatus
    else No Active Subscription
        SUB->>SUB: Show plans for purchase
    end
```

---

## 5. Cancel & Resume

### 5.1 Cancel Flow

```mermaid
sequenceDiagram
    participant U as User
    participant SUB as Subscription.vue
    participant SS as StripeService
    participant BE as Backend
    participant ST as Stripe
    
    U->>SUB: Click "Cancel Subscription"
    SUB->>SUB: confirm() dialog
    
    alt User Confirms
        SUB->>SS: cancelSubscription(subscriptionId)
        SS->>BE: POST /stripe/cancel-subscription
        BE->>ST: subscription.cancel_at_period_end = true
        ST-->>BE: Updated subscription
        BE-->>SS: { isCancelled: true, currentPeriodEnd }
        SS-->>SUB: Success
        
        SUB->>SS: checkSubscriptionStatus()
        SUB->>SUB: Show cancellation alert
        SUB-->>U: "Subscription scheduled for cancellation"
    else User Cancels Dialog
        SUB-->>U: No action
    end
```

### 5.2 Resume Flow

```mermaid
sequenceDiagram
    participant U as User
    participant SUB as Subscription.vue
    participant SS as StripeService
    participant BE as Backend
    participant ST as Stripe
    
    Note over U, ST: Subscription is in ScheduledCancel state
    U->>SUB: Click "Resume Subscription"
    SUB->>SUB: confirm() dialog
    
    alt User Confirms
        SUB->>SS: resumeSubscription(subscriptionId)
        SS->>BE: POST /stripe/resume-subscription
        BE->>ST: subscription.cancel_at_period_end = false
        ST-->>BE: Updated subscription
        BE-->>SS: { isCancelled: false }
        SS-->>SUB: Success
        
        SUB->>SS: checkSubscriptionStatus()
        SUB->>SUB: Hide cancellation alert
        SUB-->>U: "Subscription resumed successfully!"
    end
```

---

## 6. Subscription View States

### 6.1 State Machine

```mermaid
flowchart TD
    A[Loading] --> B{Check User & Subscription}
    
    B --> C{Is Admin?}
    C -->|Yes| D[Admin View with Tabs]
    C -->|No| E{Has Active Sub?}
    
    E -->|Yes| F[Show Subscription Details]
    E -->|No| G{Has Plans?}
    
    G -->|Yes| H[Show Plans for Purchase]
    G -->|No| I[Empty State]
    
    F --> J{Is Cancelled?}
    J -->|Yes| K[Show Cancellation Warning + Resume Button]
    J -->|No| L[Show Cancel Button]
    
    L --> M[Upgrade/Change Plan Option]
    K --> M
```

### 6.2 UI Components

```
┌────────────────────────────────────────────────────────────┐
│                    Your Subscription                       │
│                      ┌─────────┐                           │
│                      │ Active  │                           │
│                      └─────────┘                           │
├────────────────────────────────────────────────────────────┤
│ ⚠️ Subscription Scheduled for Cancellation                 │
│ Your subscription will end on January 31, 2026             │
│ You can resume anytime before this date.                   │
├────────────────────────────────────────────────────────────┤
│ Subscription Period                                        │
│ Start Date: January 1, 2026    End Date: January 31, 2026  │
├────────────────────────────────────────────────────────────┤
│ ┌─────────────────────┐  ┌─────────────────────┐          │
│ │   Batch Processing  │  │   Live Processing   │          │
│ │   Quota: 10 hours   │  │   Quota: 5 hours    │          │
│ │   Used: 3 hours     │  │   Used: 1 hour      │          │
│ │   ████████░░░ 30%   │  │   ████░░░░░░ 20%    │          │
│ └─────────────────────┘  └─────────────────────┘          │
├────────────────────────────────────────────────────────────┤
│  [Upgrade or Change Plan]    [Resume Subscription]         │
└────────────────────────────────────────────────────────────┘
```

---

## 7. User Service - Subscription Methods

```javascript
// user.service.js
async getUserSubscription(userId) {
  try {
    const response = await http.get(`/subscriptions/user/${userId}`)
    return response.data
  } catch (error) {
    // Return null if subscription not found (404)
    if (error.response?.status === 404) {
      return null
    }
    return this.handleApiError(error)
  }
}
```

### Subscription Object Schema

```typescript
interface Subscription {
  _id: string
  userId: string
  planId: string
  stripeSubscriptionId: string  // Reference to Stripe
  status: 'active' | 'cancelled' | 'expired'
  startDate: string             // ISO date
  endDate: string               // ISO date
  quota: {
    batchDuration: number       // seconds, -1 = unlimited
    liveDuration: number        // seconds, -1 = unlimited
  }
  usage: {
    batchDuration: number       // seconds used
    liveDuration: number        // seconds used
  }
}
```

---

## 8. Success & Cancel Pages

### 8.1 Success Page

```mermaid
flowchart LR
    A[Stripe Checkout] -->|Payment Success| B[/success]
    B --> C[Display Success Message]
    C --> D[Return to Home Button]
    D --> E[Navigate to Dashboard]
```

### 8.2 Cancel Page

```mermaid
flowchart LR
    A[Stripe Checkout] -->|User Cancels| B[/cancel]
    B --> C[Display Cancel Message]
    C --> D[Return to Home]
    C --> E[Try Again]
    E --> F[Go Back to Previous Page]
```

---

## 9. Related Files

| File | Description |
|------|-------------|
| [stripe.service.js](file:///home/linh/Workspaces/gateway-dashboard/src/services/stripe.service.js) | Stripe API integration |
| [user.service.js](file:///home/linh/Workspaces/gateway-dashboard/src/services/user.service.js) | User & subscription queries |
| [Subscription.vue](file:///home/linh/Workspaces/gateway-dashboard/src/views/Subscription.vue) | Main subscription page |
| [PlanCard.vue](file:///home/linh/Workspaces/gateway-dashboard/src/components/PlanCard.vue) | Plan display component |
| [Success.vue](file:///home/linh/Workspaces/gateway-dashboard/src/views/Success.vue) | Payment success page |
| [Cancel.vue](file:///home/linh/Workspaces/gateway-dashboard/src/views/Cancel.vue) | Payment cancelled page |

---

*[← Back to Index](./README.md)*
