# Fix last WireGuard reference in login screen

**What's needed:**

There's one remaining old reference to "WireGuard Proxy" in the login screen footer text. Everything else is already clean.

**Change:**
- Update the footer text on the login screen from **"iOS 26+ | WebKit Playwright | WireGuard Proxy"** to **"iOS 26+ | WebKit Playwright | NordVPN External"** to match the current architecture.

That's the only remaining cleanup needed — all other Wire/proxy/OpenVPN/OVPN references are gone from the live project code.