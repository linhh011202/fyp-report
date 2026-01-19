# API Reference

## 1. Authentication

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `/auth/register` | POST | ❌ | Register account |
| `/auth/login` | POST | ❌ | Login |
| `/auth/refresh-token` | POST | ❌ | Refresh expired token |
| `/auth/verify-token` | POST | ❌ | Verify token validity |
| `/auth/logout` | POST | ✅ | Logout and revoke |
| `/auth/google/login` | GET | ❌ | Start Google OAuth |
| `/auth/apple/callback` | POST | ❌ | Apple OAuth callback |
| `/auth/add-info` | POST | ❌ | Complete OAuth signup |

### Login Request/Response

```javascript
// POST /auth/login
Request: { email: "user@email.com", password: "secret" }
Response: { accessToken: "jwt...", subscriptionEnd: 1737244800, isVerified: true }
```

---

## 2. Stripe

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `/stripe/stripe-checkout-session` | POST | ✅ | Create checkout session |
| `/stripe/check-subscription-status` | POST | ✅ | Check subscription |
| `/stripe/cancel-subscription` | POST | ✅ | Cancel subscription |
| `/stripe/resume-subscription` | POST | ✅ | Resume subscription |
| `/stripe/get-price` | POST | ❌ | Get Stripe price info |

### Create Checkout Session

```javascript
// POST /stripe/stripe-checkout-session
Request: { priceId: "price_xxx" }
Response: { url: "https://checkout.stripe.com/...", sessionId: "cs_xxx" }
```

---

## 3. Plans

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `/plans/latest` | GET | ❌ | Get latest plans |
| `/plans` | POST | ✅ Admin | Create new plans |

### Get Latest Plans

```javascript
// GET /plans/latest
Response: {
  data: {
    version: 3,
    plans: "{\"plans\":[...]}"  // JSON string
  }
}
```

---

## 4. Users & Subscriptions

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `/users/current` | GET | ✅ | Get current user |
| `/subscriptions/user/:id` | GET | ✅ | Get user subscription |

### Get Subscription

```javascript
// GET /subscriptions/user/:id
Response: {
  _id: "...",
  userId: "...",
  stripeSubscriptionId: "sub_xxx",
  status: "active",
  startDate: "2025-01-01T00:00:00Z",
  endDate: "2025-02-01T00:00:00Z",
  quota: { batchDuration: 3600, liveDuration: 1800 },
  usage: { batchDuration: 1200, liveDuration: 600 }
}
```

---

## 5. Environment Variables

| Variable | Description |
|----------|-------------|
| `VUE_APP_GATEWAY_URL` | Backend API base URL |
| `VUE_APP_APPLE_CLIENT_ID` | Apple Sign-In client ID |
| `DNS_URL` | Frontend DNS URL |

---

*[← Back to Index](./README.md)*
