# Authentication System

## Tổng Quan

Hệ thống authentication hỗ trợ 3 phương thức đăng nhập:
- **Email/Password**: Đăng ký và đăng nhập truyền thống
- **Google OAuth 2.0**: Redirect-based OAuth flow
- **Apple Sign-In**: SDK-based với redirect callback

---

## 1. Authentication Flow Overview

```mermaid
sequenceDiagram
    participant U as User
    participant FE as Vue Frontend
    participant AS as Auth Service
    participant BE as Backend API
    participant OAuth as OAuth Provider
    
    Note over U, OAuth: Option 1: Email/Password Login
    U->>FE: Enter credentials
    FE->>AS: authService.login()
    AS->>BE: POST /auth/login
    BE-->>AS: { accessToken, subscriptionEnd, isVerified }
    AS->>AS: storeAuthData()
    AS-->>FE: Success
    FE->>FE: Navigate to Dashboard
    
    Note over U, OAuth: Option 2: Google OAuth
    U->>FE: Click Google Sign-In
    FE->>AS: initiateGoogleLogin()
    AS->>OAuth: Redirect to Google
    OAuth-->>BE: Callback with code
    BE-->>FE: Redirect with token in URL
    FE->>AS: storeAuthData()
    
    Note over U, OAuth: Option 3: Apple Sign-In
    U->>FE: Click Apple Sign-In
    FE->>AS: initiateAppleLogin()
    AS->>OAuth: Apple SDK signIn()
    OAuth-->>BE: POST callback
    BE-->>FE: Redirect with token
```

---

## 2. Auth Service Architecture

### 2.1 Class Diagram

```mermaid
classDiagram
    class AuthService {
        +register(data) Promise
        +login(data) Promise
        +refreshToken(data) Promise
        +verifyToken(data) Promise
        +logout(token) Promise
        +storeAuthData(token, subEnd, isVerified)
        +getAccessToken() string
        +getSubscriptionEnd() number
        +getIsVerified() boolean
        +clearAuthData()
        +isAuthenticated() boolean
        +initiateGoogleLogin()
        +initiateAppleLogin() Promise
        +initializeAppleSignIn(clientId) boolean
        +setPassword(token, password, fullname) Promise
        -handleApiError(error)
    }
    
    class LocalStorage {
        +accessToken: string
        +jwt: string
        +subscriptionEnd: string
        +isVerified: string
    }
    
    AuthService --> LocalStorage : manages
```

### 2.2 Methods Detail

| Method | Description | Params | Returns |
|--------|-------------|--------|---------|
| `register` | Đăng ký tài khoản mới | `{name, email, password}` | `{message, user?}` |
| `login` | Đăng nhập email/password | `{email, password}` | `{accessToken, subscriptionEnd, isVerified}` |
| `refreshToken` | Làm mới token hết hạn | `{token}` | `{accessToken, subscriptionEnd, isVerified}` |
| `verifyToken` | Xác thực token | `{token}` | `{valid, expired?, message?}` |
| `logout` | Đăng xuất và revoke token | `token` | `{message}` |
| `setPassword` | Hoàn tất OAuth signup | `token, password, fullname` | `{accessToken, ...}` |

---

## 3. Token Management

### 3.1 Token Lifecycle

```mermaid
flowchart TD
    A[App Start] --> B{Has Token?}
    B -->|Yes| C[Verify Token]
    B -->|No| D[Redirect to SignIn]
    
    C --> E{Token Valid?}
    E -->|Yes| F[Continue to App]
    E -->|Expired| G[Refresh Token]
    E -->|Invalid| D
    
    G --> H{Refresh Success?}
    H -->|Yes| I[Store New Token]
    H -->|No| D
    
    I --> F
    
    subgraph "Automatic Verification"
        J[Every 5 Minutes] --> C
    end
```

### 3.2 Storage Schema

```javascript
// LocalStorage keys
{
  accessToken: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  jwt: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...", // backward compat
  subscriptionEnd: "1737244800000", // Unix timestamp (ms)
  isVerified: "true"
}
```

### 3.3 Automatic Token Refresh

```javascript
// main.js - Token verification interval
if (authService.isAuthenticated()) {
  app.verifyAndRefreshToken()
  setInterval(() => {
    app.verifyAndRefreshToken()
  }, 5 * 60 * 1000) // Every 5 minutes
}
```

---

## 4. Email/Password Authentication

### 4.1 Login Flow

```mermaid
sequenceDiagram
    participant U as User
    participant SI as SignIn.vue
    participant AS as AuthService
    participant BE as Backend
    
    U->>SI: Enter email + password
    U->>SI: Click "Sign in"
    SI->>SI: Validate inputs
    
    alt Invalid Input
        SI-->>U: Show error message
    else Valid Input
        SI->>AS: login({email, password})
        AS->>BE: POST /auth/login
        
        alt Success
            BE-->>AS: {accessToken, subscriptionEnd, isVerified}
            AS->>AS: storeAuthData()
            AS-->>SI: Success
            SI->>SI: router.push('/')
        else Error
            BE-->>AS: Error response
            AS-->>SI: Throw error
            SI-->>U: Show error message
        end
    end
```

### 4.2 Registration Flow

```mermaid
sequenceDiagram
    participant U as User
    participant SU as SignUp.vue
    participant AS as AuthService
    participant BE as Backend
    
    U->>SU: Enter name, email, password
    U->>SU: Click "Sign up"
    SU->>SU: Validate inputs
    
    SU->>AS: register({name, email, password})
    AS->>BE: POST /auth/register
    
    alt Registration Success with Token
        BE-->>AS: {accessToken, user}
        AS->>AS: storeAuthData()
        SU-->>U: "Registration successful!"
        SU->>SU: Navigate to Dashboard
    else Registration Success - Need Verification
        BE-->>AS: {message, user}
        SU-->>U: Show success message
        SU->>SU: Navigate to SignIn after 3s
    else Registration Failed
        BE-->>AS: Error
        SU-->>U: Show error message
    end
```

---

## 5. OAuth Authentication

### 5.1 Google OAuth Flow

```mermaid
sequenceDiagram
    participant U as User
    participant FE as SignIn/SignUp.vue
    participant AS as AuthService
    participant BE as Backend
    participant G as Google OAuth
    
    U->>FE: Click Google icon
    FE->>AS: initiateGoogleLogin()
    
    Note over AS: Build redirect URL
    AS->>AS: url = API_URL + '/auth/google/login?redirect=' + frontendUrl
    AS->>G: window.location.href = url
    
    G->>G: User authenticates
    G->>BE: Callback with auth code
    
    BE->>BE: Exchange code for tokens
    BE->>BE: Create/find user
    BE->>BE: Generate JWT
    
    alt Existing User
        BE-->>FE: Redirect to /sign-in?token=XXX
        FE->>AS: storeAuthData(token, ...)
        FE->>FE: Navigate to Dashboard
    else New User (needs password)
        BE-->>FE: Redirect to /complete-signup?token=XXX
    end
```

### 5.2 Apple Sign-In Flow

```mermaid
sequenceDiagram
    participant U as User
    participant FE as SignIn/SignUp.vue
    participant AS as AuthService
    participant Apple as Apple SDK
    participant BE as Backend
    
    Note over FE: On component mount
    FE->>AS: initializeAppleSignIn()
    AS->>Apple: AppleID.auth.init({clientId, scope, redirectURI})
    
    U->>FE: Click Apple icon
    FE->>AS: initiateAppleLogin()
    AS->>Apple: AppleID.auth.signIn()
    
    Apple->>Apple: User authenticates
    Apple->>BE: POST /auth/apple/callback
    
    BE->>BE: Verify Apple token
    BE->>BE: Create/find user
    BE-->>FE: Redirect with token
```

### 5.3 OAuth Complete Signup

Khi user đăng nhập OAuth lần đầu, cần complete signup bằng cách đặt password:

```mermaid
sequenceDiagram
    participant U as User
    participant CS as CompleteSignup.vue
    participant AS as AuthService
    participant BE as Backend
    
    Note over U, BE: User redirected with temporaryToken
    CS->>CS: Extract token from URL query
    CS->>CS: Check if already authenticated
    
    U->>CS: Enter fullName + password + confirmPassword
    U->>CS: Click "Create Account"
    
    CS->>CS: Validate inputs
    
    alt Passwords don't match
        CS-->>U: "Passwords do not match"
    else Password too short
        CS-->>U: "Password must be at least 6 characters"
    else Valid
        CS->>AS: setPassword(temporaryToken, password, fullName)
        AS->>BE: POST /auth/add-info
        
        alt Success
            BE-->>AS: {accessToken, subscriptionEnd, isVerified}
            AS->>AS: storeAuthData()
            AS->>AS: localStorage.removeItem('temporaryToken')
            CS-->>U: "Account successfully created!"
            CS->>CS: Navigate to /speeches
        else Token Expired
            CS-->>U: "Token expired. Please sign in again."
        else User Exists
            CS-->>U: "User already exists. Please login."
            CS->>CS: Navigate to /sign-in
        end
    end
```

---

## 6. Apple Sign-In SDK Initialization

```javascript
// auth.service.js
initializeAppleSignIn(clientId) {
  if (!window.AppleID) {
    console.warn('Apple Sign-In SDK not loaded yet')
    return false
  }

  try {
    const appleClientId = clientId || process.env.VUE_APP_APPLE_CLIENT_ID

    window.AppleID.auth.init({
      clientId: appleClientId,           // 'sg.speechlab.gateway'
      scope: 'name email',
      redirectURI: `${API_URL}/auth/apple/callback`,
      usePopup: false                     // Use redirect mode
    })
    return true
  } catch (error) {
    console.error('Failed to initialize Apple Sign-In:', error)
    return false
  }
}
```

---

## 7. Auth Mixin

Vue mixin cung cấp authentication functionality cho components:

```mermaid
classDiagram
    class AuthMixin {
        -authTokenCheckInterval: Timer
        +isAuthenticated: boolean
        +accessToken: string
        +subscriptionEnd: number
        +isVerified: boolean
        +logout() Promise
        +verifyAndRefreshToken() Promise
        +startTokenVerification()
        +stopTokenVerification()
    }
    
    note for AuthMixin "Auto-starts verification on mount\nCleans up on beforeDestroy"
```

### Usage

```javascript
import { authMixin } from '@/mixins/auth.mixin'

export default {
  mixins: [authMixin],
  // Component now has access to:
  // - this.isAuthenticated
  // - this.accessToken
  // - this.logout()
  // - etc.
}
```

---

## 8. Related Files

| File | Description |
|------|-------------|
| [auth.service.js](file:///home/linh/Workspaces/gateway-dashboard/src/services/auth.service.js) | Core auth service |
| [auth.mixin.js](file:///home/linh/Workspaces/gateway-dashboard/src/mixins/auth.mixin.js) | Auth mixin for components |
| [SignIn.vue](file:///home/linh/Workspaces/gateway-dashboard/src/views/SignIn.vue) | Login page |
| [SignUp.vue](file:///home/linh/Workspaces/gateway-dashboard/src/views/SignUp.vue) | Registration page |
| [CompleteSignup.vue](file:///home/linh/Workspaces/gateway-dashboard/src/views/CompleteSignup.vue) | OAuth completion page |
| [main.js](file:///home/linh/Workspaces/gateway-dashboard/src/main.js) | Token verification setup |

---

*[← Back to Index](./README.md)*
