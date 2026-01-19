# FYP Report Structure Plan

This plan outlines the structure for your Final Year Project report, organizing the provided documentation into logical chapters and sections.

## Proposed Structure

I will create the following directory structure and LaTeX files in your `tex/` folder.

### **Chapter 1: Introduction**
*   **File:** `tex/intro.tex` (Existing)
*   **Content:** Already exists.

### **Chapter 2: System Architecture**
*   **Folder:** `tex/ch2_architecture/`
*   **Files:**
    *   `01_overview.tex`: High-level architecture (Frontend/Backend/External Services)
    *   `02_tech_stack.tex`: Technologies used (NestJS, Vue.js, Stripe, Redis, MongoDB)
    *   `03_database.tex`: Database schema design (Users, Subscriptions, Plans, Tokens)

### **Chapter 3: Authentication and Security**
*   **Folder:** `tex/ch3_auth/`
*   **Files:**
    *   `01_overview.tex`: Authentication flows (Email, Google SSO, Apple SSO)
    *   `02_implementation.tex`: Implementation details (Guards, Strategies, Controllers)
    *   `03_token_management.tex`: JWT lifecycle, Refresh tokens, Blacklisting
    *   `04_security.tex`: Session security and verification

### **Chapter 4: Subscription and Payment**
*   **Folder:** `tex/ch4_payment/`
*   **Files:**
    *   `01_stripe_integration.tex`: Stripe Checkout, Webhooks, Product/Price sync
    *   `02_subscription_lifecycle.tex`: Creation, Cancellation, Resuming, Quota tracking
    *   `03_plans_management.tex`: Admin JSON editor, versioning, validation

### **Chapter 5: Frontend Implementation**
*   **Folder:** `tex/ch5_frontend/`
*   **Files:**
    *   `01_components.tex`: Component architecture (Layouts, PlanCard)
    *   `02_routing.tex`: Navigation guards, Route configuration
    *   `03_services.tex`: HTTP Client, API services, State management

### **Chapter 6: Conclusion**
*   **Folder:** `tex/ch6_conclusion/`
*   **Files:**
    *   `conclusion.tex`: Summary of achievements and future work

---

## Action Plan

1.  **Create Directories**: Create `tex/ch2_architecture`, `tex/ch3_auth`, etc.
2.  **Generate Files**: Create the `.tex` files listed above.
    *   I will populate them with initial content derived from your Markdown documentation, converted to valid LaTeX.
3.  **Update `main.tex`**: Add `\input{...}` commands for all new chapters.
