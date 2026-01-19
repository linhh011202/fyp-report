# Token Management (PR #10)

Các API mới để quản lý JWT token lifecycle.

## Overview

```mermaid
flowchart LR
    subgraph "Token Lifecycle"
        LOGIN[Login] --> ACTIVE[Active Token]
        ACTIVE --> VERIFY{Verify}
        ACTIVE --> REFRESH[Refresh]
        ACTIVE --> LOGOUT[Logout]
        REFRESH --> ACTIVE
        LOGOUT --> BLACKLIST[Blacklisted]
    end
```

---

# API: POST /auth/logout

Revoke token hiện tại, thêm vào blacklist.

## Sequence Diagram

```mermaid
sequenceDiagram
    participant Client
    participant Guard as JwtAuthGuard
    participant Controller as AuthController
    participant Auth as AuthService
    participant JWT as JwtService
    participant DB as MongoDB

    Client->>Controller: POST /auth/logout<br/>Authorization: Bearer xxx
    
    Controller->>Guard: @UseGuards(JwtAuthGuard)
    Guard->>Guard: Validate JWT
    Guard->>DB: Find user by token.sub
    Guard-->>Controller: req.user = user
    
    Controller->>Controller: Extract token from header
    
    alt No token
        Controller-->>Client: 401 No token provided
    end
    
    Controller->>Auth: logout(token, userId)
    Auth->>JWT: decode(token)
    JWT-->>Auth: {exp, sub, ...}
    
    Auth->>DB: Insert to TokenBlacklist
    Note over DB: {token, userId, expiresAt, reason: 'logout'}
    
    Auth->>DB: Delete from UserTokens
    
    Auth-->>Controller: void
    Controller-->>Client: 200 OK
```

## Request

```http
POST /auth/logout
Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
```

## Response

```json
{
  "statusCode": 200,
  "message": "Logged out successfully. Your access token has been revoked."
}
```

## Implementation

```typescript
// auth.controller.ts
@UseGuards(JwtAuthGuard)
@HttpCode(HttpStatus.OK)
@Post('/logout')
async logout(@Req() req: IRequest) {
  // Extract token from Authorization header
  const authHeader = req.headers.authorization
  const token = authHeader?.replace('Bearer ', '')

  if (!token) {
    throw new UnauthorizedException('No token provided')
  }

  await this.authService.logout(token, req.user._id.toString())

  return {
    statusCode: HttpStatus.OK,
    message: 'Logged out successfully. Your access token has been revoked.',
  }
}
```

```typescript
// auth.service.ts
async logout(token: string, userId: string): Promise<void> {
  // Decode token to get expiration
  const decoded: any = this.jwtService.decode(token)

  if (!decoded || !decoded.exp) {
    throw new UnauthorizedException('Invalid token')
  }

  // Add token to blacklist
  await this.tokenBlacklistModel.create({
    token,
    userId,
    expiresAt: new Date(decoded.exp * 1000),
    reason: 'logout',
  })

  // Remove from active tokens
  await this.userTokenModel.deleteOne({ token })
}
```

---

# API: POST /auth/refresh-token

Làm mới token đã expired (signature vẫn phải valid).

## Sequence Diagram

```mermaid
sequenceDiagram
    participant Client
    participant Controller as AuthController
    participant Auth as AuthService
    participant JWT as JwtService
    participant App as ApplicationService
    participant DB as MongoDB

    Client->>Controller: POST /auth/refresh-token<br/>{token: "expired-token"}
    
    Controller->>Auth: refreshAccessToken(expiredToken)
    
    Auth->>JWT: decode(expiredToken)
    Note over JWT: Decode without verify
    JWT-->>Auth: {sub, exp, aud, ...}
    
    alt Invalid format
        Auth-->>Controller: 401 Invalid token
    end
    
    Auth->>DB: Check TokenBlacklist
    
    alt Token blacklisted
        DB-->>Auth: found
        Auth-->>Controller: 401 Cannot refresh revoked token
    end
    
    Auth->>DB: Find user by sub
    
    alt User not found
        Auth-->>Controller: 401 User not found
    end
    
    Auth->>JWT: verify(token, {ignoreExpiration: true})
    Note over JWT: Verify signature only
    
    alt Has audience (third-party app)
        Auth->>App: findById(aud)
        App-->>Auth: app with publicKey
        Auth->>JWT: verify with app's publicKey
    end
    
    alt Signature invalid
        Auth-->>Controller: 401 Invalid token
    end
    
    Auth->>DB: Insert old token to TokenBlacklist
    Note over DB: reason: 'refresh'
    
    Auth->>DB: Delete old token from UserTokens
    
    Auth->>JWT: sign(newPayload, options)
    JWT-->>Auth: newToken
    
    Auth->>DB: Insert new token to UserTokens
    
    Auth-->>Controller: {accessToken, subscriptionEnd, isVerified}
    Controller-->>Client: 200 OK
```

## Request

```json
{
  "token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

## Response

```json
{
  "accessToken": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  "subscriptionEnd": 1705651200000,
  "isVerified": true
}
```

## Implementation

```typescript
// auth.controller.ts
@Post('/refresh-token')
async refreshToken(@Body() body: { token: string }) {
  return this.authService.refreshAccessToken(body.token)
}
```

```typescript
// auth.service.ts
async refreshAccessToken(expiredToken: string) {
  // Decode (don't verify - may be expired)
  const decoded: any = this.jwtService.decode(expiredToken)

  if (!decoded || !decoded.sub) {
    throw new UnauthorizedException('Invalid token')
  }

  // Check blacklist
  const blacklisted = await this.tokenBlacklistModel.findOne({
    token: expiredToken,
  })
  if (blacklisted) {
    throw new UnauthorizedException('Cannot refresh a revoked token. Please login again.')
  }

  // Get user
  const user = await this.userService.findById(decoded.sub)
  if (!user) {
    throw new UnauthorizedException('User not found')
  }

  // Verify signature (ignore expiration)
  const options: any = { ignoreExpiration: true }

  if (decoded.aud) {
    const app = await this.appService.findById(decoded.aud, true)
    if (!app) {
      throw new UnauthorizedException('Application not found')
    }
    options.publicKey = (app.key as Key).publicKey
    options.audience = app._id.toString()
  }

  this.jwtService.verify(expiredToken, options)

  // Blacklist old token
  if (decoded.exp) {
    await this.tokenBlacklistModel.create({
      token: expiredToken,
      userId: user._id.toString(),
      expiresAt: new Date(decoded.exp * 1000),
      reason: 'refresh',
    })
  }

  // Remove old token from active
  await this.userTokenModel.deleteOne({ token: expiredToken })

  // Generate new token
  const payload = {
    email: user.email,
    role: user.role,
    name: user.name,
    type: user.type,
  }
  const newOptions: any = { subject: user._id.toString() }

  // Preserve third-party app context
  if (decoded.aud) {
    const app = await this.appService.findById(decoded.aud, true)
    if (app) {
      newOptions.audience = app._id.toString()
      newOptions.keyid = (app.key as Key)._id.toString()
      newOptions.privateKey = (app.key as Key).privateKey
    }
  }

  const newToken = this.jwtService.sign(payload, newOptions)
  const newDecoded: any = this.jwtService.decode(newToken)

  // Save new token
  await this.userTokenModel.create({
    userId: user._id.toString(),
    token: newToken,
    expiresAt: new Date(newDecoded.exp * 1000),
  })

  return {
    accessToken: newToken,
    subscriptionEnd: (await this.subscriptionService.findByUser(user._id.toString())).endDate.getTime(),
    isVerified: user.isVerified,
  }
}
```

---

# API: POST /auth/verify-token

Kiểm tra token có valid không (public endpoint).

## Sequence Diagram

```mermaid
sequenceDiagram
    participant Client
    participant Controller as AuthController
    participant Auth as AuthService
    participant JWT as JwtService
    participant App as ApplicationService
    participant DB as MongoDB

    Client->>Controller: POST /auth/verify-token<br/>{token: "xxx"}
    
    Controller->>Auth: verifyAccessToken(token)
    
    Auth->>JWT: decode(token)
    
    alt Invalid format
        JWT-->>Auth: null
        Auth-->>Controller: {valid: false, message: "Invalid format"}
    end
    
    JWT-->>Auth: {sub, exp, aud, ...}
    
    Auth->>Auth: Check expiration
    Note over Auth: exp < now?
    
    alt Expired
        Auth-->>Controller: {valid: false, expired: true}
    end
    
    Auth->>DB: Check TokenBlacklist
    
    alt Blacklisted
        DB-->>Auth: found
        Auth-->>Controller: {valid: false, message: "Token revoked"}
    end
    
    Auth->>DB: Find user by sub
    
    alt User not found
        Auth-->>Controller: {valid: false, message: "User not found"}
    end
    
    alt Has audience
        Auth->>App: findById(aud)
        App-->>Auth: app with publicKey
    end
    
    Auth->>JWT: verify(token, options)
    
    alt Signature invalid
        Auth-->>Controller: {valid: false, message: "Verification failed"}
    end
    
    Auth-->>Controller: {valid: true, user: {...}, expiresAt}
    Controller-->>Client: 200 OK
```

## Request

```json
{
  "token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

## Response (Valid)

```json
{
  "statusCode": 200,
  "valid": true,
  "expired": false,
  "user": {
    "id": "64a1b2c3d4e5f6g7h8i9j0k2",
    "email": "user@example.com",
    "role": "user",
    "name": "John Doe",
    "type": "trial",
    "isVerified": true
  },
  "expiresAt": 1705651200000,
  "message": "Token is valid"
}
```

## Response (Expired)

```json
{
  "statusCode": 401,
  "valid": false,
  "expired": true,
  "user": null,
  "expiresAt": 1705564800000,
  "message": "Access token has expired"
}
```

## Response (Revoked)

```json
{
  "statusCode": 401,
  "valid": false,
  "expired": false,
  "user": null,
  "expiresAt": 1705651200000,
  "message": "Access token has been revoked"
}
```

## Implementation

```typescript
// auth.controller.ts
@Post('/verify-token')
async verifyToken(@Body() body: { token: string }) {
  return this.authService.verifyAccessToken(body.token)
}
```

```typescript
// auth.service.ts
async verifyAccessToken(token: string) {
  try {
    const decoded: any = this.jwtService.decode(token)

    if (!decoded) {
      return {
        statusCode: 400,
        valid: false,
        expired: false,
        user: null,
        expiresAt: null,
        message: 'Invalid token format',
      }
    }

    // Check expiration
    const now = Math.floor(Date.now() / 1000)
    if (decoded.exp && decoded.exp < now) {
      return {
        statusCode: 401,
        valid: false,
        expired: true,
        user: null,
        expiresAt: decoded.exp * 1000,
        message: 'Access token has expired',
      }
    }

    // Check blacklist
    const blacklisted = await this.tokenBlacklistModel.findOne({ token })
    if (blacklisted) {
      return {
        statusCode: 401,
        valid: false,
        expired: false,
        user: null,
        expiresAt: decoded.exp * 1000,
        message: 'Access token has been revoked',
      }
    }

    // Get user
    const user = await this.userService.findById(decoded.sub)
    if (!user) {
      return {
        statusCode: 404,
        valid: false,
        expired: false,
        user: null,
        expiresAt: decoded.exp * 1000,
        message: 'User not found',
      }
    }

    // Verify signature
    const options: any = {}
    if (decoded.aud) {
      const app = await this.appService.findById(decoded.aud, true)
      if (!app) {
        return { statusCode: 404, valid: false, message: 'Application not found' }
      }
      options.publicKey = (app.key as Key).publicKey
      options.audience = app._id.toString()
    }

    this.jwtService.verify(token, options)

    return {
      statusCode: 200,
      valid: true,
      expired: false,
      user: {
        id: user._id.toString(),
        email: user.email,
        role: user.role,
        name: user.name,
        type: user.type,
        isVerified: user.isVerified,
      },
      expiresAt: decoded.exp * 1000,
      message: 'Token is valid',
    }
  } catch (error) {
    return {
      statusCode: 400,
      valid: false,
      expired: false,
      user: null,
      expiresAt: null,
      message: error.message || 'Token verification failed',
    }
  }
}
```

---

# Error Summary

| API | Error | Code | Cause |
|-----|-------|------|-------|
| `/logout` | No token provided | 401 | Missing Authorization header |
| `/logout` | Invalid token | 401 | Token cannot be decoded |
| `/refresh-token` | Invalid token | 401 | Token format invalid |
| `/refresh-token` | Cannot refresh revoked token | 401 | Token in blacklist |
| `/refresh-token` | User not found | 401 | User deleted |
| `/verify-token` | Token expired | 401 | exp < now |
| `/verify-token` | Token revoked | 401 | Token in blacklist |
