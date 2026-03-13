# AGENT.md
Project: YouTube-Only Brave-Style Browser
Platform: Android (Flutter + Native Android)
Priority: Performance / Security / Minimalism

---

## Mandatory Reading

Before modifying any code the agent MUST read:

1. AGENTS_RULES.md
2. AGENTS_ADBLOCK.md
3. AGENTS_ARCHITECTURE.md

These files define the development rules.


# 1. PROJECT GOAL

Build a **single-purpose browser application** that behaves like a simplified Brave browser
but allows browsing **only YouTube domains**.

This is NOT a full browser.

The application must:

• Load YouTube reliably  
• Prevent navigation outside allowed domains  
• Block ads/trackers using Brave adblock engine when possible  
• Support Android Picture-in-Picture  
• Remain minimal and maintainable

The system should borrow ideas from Brave architecture but **not replicate Brave entirely**.

---

# 2. PRIMARY DESIGN PRINCIPLES

1. Single-domain browsing
2. Security-first architecture
3. Brave-style blocking layer
4. Minimal UI
5. Maintainable modular architecture
6. Avoid unnecessary browser features

---

# 3. ARCHITECTURE OVERVIEW

The application architecture is divided into these layers:

Application Layer
│
├── Browser Layer
│   WebView rendering
│
├── Domain Policy Layer
│   Navigation filtering
│
├── Brave-style Blocking Layer
│   Ad/tracker blocking
│
├── Media Layer
│   Video lifecycle
│   PiP integration
│
├── Session Layer
│   Cookies and auth
│
└── UI Layer
    Minimal controls

---

# 4. ALLOWED DOMAINS

Allowed domains must include:

youtube.com  
www.youtube.com  
m.youtube.com  
youtu.be  

Additional subdomains must be allowed **only if necessary** for playback or authentication.

External navigation must be blocked.

---

# 5. FEATURES THAT MUST EXIST

## Browser Core

• WebView or Chromium-based rendering
• JavaScript enabled
• Cookie storage
• Session persistence
• Page lifecycle management
• Error handling

---

## Domain Lock System

Every navigation event must pass a domain policy check.

Required components:

DomainPolicyService
URLValidator
NavigationInterceptor

If URL not allowed:

BLOCK navigation

or

REDIRECT to internal error page

---

## Brave-style Blocking System

The project should use **Brave adblock-rust engine when possible**.

Capabilities expected:

Network request filtering  
Cosmetic filtering (optional)  
Rule list loading  
Compiled rule caching  

The system must be separated into:

AdblockService
FilterListLoader
AdblockEngineBridge

Blocking decision should happen BEFORE requests are executed.

---

## Media Layer

The browser must detect video playback state.

Required:

Video detection
Fullscreen support
Background playback support
Android PiP integration

PiP must be implemented using **Android native Picture-in-Picture API**.

Flutter must communicate with Android using platform channels.

---

## Session Layer

Must support:

Cookies
LocalStorage
SessionStorage
YouTube login flow

---

# 6. MINIMAL UI REQUIREMENTS

Allowed UI elements:

Back button  
Refresh button  
Loading indicator  
Error screen  
Settings screen  

Do NOT implement:

Tabs
Bookmarks
History UI
Address bar
Search suggestions
Download manager

---

# 7. SECURITY REQUIREMENTS

The system must prevent:

External domain navigation  
Unsafe URL schemes  
File system exposure  
Unrestricted JS bridges  
External app launches without validation  

Only HTTPS URLs should be accepted where possible.

---

# 8. SETTINGS

Minimal settings allowed:

Adblock toggle  
Clear session/cache  
PiP enable/disable  

Nothing else.

---

# 9. FEATURES THAT MUST NOT EXIST

The following must NOT be implemented:

Tabs
Bookmarks
History
Sync
Wallet
Rewards
VPN
AI assistants
Extensions
Multi-profile
Password manager
Search engine selection
General browsing

---

# 10. MODULE STRUCTURE

lib/

app/
routes/
config/

features/

browser/
domain_lock/
adblock/
pip/
session/
settings/

shared/

utils/
constants/
platform/

---

# 11. DEVELOPMENT RULES

1. Keep code minimal and modular
2. Avoid unnecessary dependencies
3. Use platform channels for Android features
4. Separate domain logic from UI
5. Document non-obvious logic
6. Prioritize reliability over feature count

---

# 12. IMPLEMENTATION ORDER

1. Project skeleton
2. Browser screen
3. Domain lock
4. Media detection
5. PiP integration
6. Adblock integration
7. Minimal settings

---

# 13. SUCCESS CRITERIA

The project is complete when:

• YouTube loads correctly
• External navigation is blocked
• Login works
• Video playback works
• Fullscreen works
• PiP works
• Adblock layer is integrated
• App remains minimal

# 14. การวิเคราะห์และแก้ไขปัญหาให้อ่านค่าจากterminalก่อน
• ให้อ่านค่าจากterminalที่ทดสอบล่าสุดก่อนทุกครั้งแล้วจึงค่อยวิเคราะห์/หาสาเหตุในส่วนอื่นๆต่อไป