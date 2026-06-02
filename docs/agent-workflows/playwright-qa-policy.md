# Playwright QA Policy

QA must use Playwright for browser-facing validation.

## Required For

- UI flows
- Authentication and authorization journeys
- Forms and validation
- Navigation and routing
- Dashboards and data views
- Checkout, booking, payment, or other critical conversion paths
- Regression checks for browser-facing bugs
- Release validation for web features

## Evidence Required

QA reports must include:

- Playwright command
- Environment URL
- Browser/device/project used
- Test data or account assumptions
- Pass/fail result
- Report, trace, screenshot, or video path when available
- Bug reproduction steps when failing

## Exceptions

QA may skip Playwright only when:

- The work is not browser-facing, or
- Playwright cannot run due to an environment/tooling blocker, and
- Tech Lead accepts the documented exception.

When blocked, QA must report:

- Exact command attempted
- Exact error
- Environment details
- Suspected owner
- Next action

Manual testing can supplement Playwright, but it does not replace Playwright for critical browser flows.
