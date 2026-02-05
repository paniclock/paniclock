# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability, please click the ["Report a vulnerability"](https://github.com/paniclock/paniclock/security/advisories/new) button to open the advisory form.


## Security Model

PanicLock uses a privileged helper installed via SMJobBless that:

- Only executes 3 hardcoded system commands (`bioutil`, `pmset`, `CGSession`)
- Verifies connecting apps via code signature, bundle ID, and team ID
- Operates fully offline with no network activity or telemetry
