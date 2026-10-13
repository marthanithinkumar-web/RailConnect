# RailConnect

RailConnect is being built as a real public community website where travellers can find people planning a similar journey and coordinate through private in-app messages. It is **not** a ticket marketplace, railway booking service, or official Indian Railways/IRCTC service.

## Current architecture

- Responsive static frontend hosted on GitHub Pages.
- Supabase Auth for accounts and persistent Postgres storage.
- Row Level Security (RLS) protects ownership and private conversations.
- No seeded/sample journeys: explore is empty until real users publish actual plans.
- Private messaging; email addresses are not shown on public journey cards.
- No PNR, ticket/identity document uploads, payments, or ticket transfer/resale features.

## Required setup before this becomes live

The GitHub Pages frontend and Supabase database are separate services. A Supabase project has **not** been connected to this repository yet.

1. Create a Supabase project at https://supabase.com/dashboard in an organization you control. Choose a region appropriate for your audience (Mumbai/India region if available in your account and plan).
2. In Supabase SQL Editor, run the complete schema in `supabase/schema.sql`. Inspect the result and confirm all four public tables have RLS enabled.
3. In Supabase Project Settings / API, copy the Project URL and the **publishable key** (or legacy anon key). Never use a service-role/secret key in a browser.
4. Replace the two placeholders in `config.js` with those public values and commit the file to the repository. The URL and publishable/anon key are intentionally public; database RLS is the security boundary.
5. In Supabase Authentication settings, configure the site URL and allowed redirect URLs to include `https://marthanithinkumar-web.github.io/RailConnect/`. Set up email confirmation and review rate limits.
6. In GitHub repository Settings → Pages, set Build and deployment Source to **GitHub Actions**. Check Actions for a successful Pages deployment.
7. Test with two separate accounts: create a journey with account A; search and message it with account B; verify A and B can only see their own conversations and only the owner can update/cancel their journey. Test email confirmation and mobile layout.

## Features implemented in the frontend

- Search by origin, destination, and travel date.
- Real journey cards from the Supabase database only; no demo data is fabricated.
- Email/password sign-up and sign-in.
- Create and cancel your own journey posts.
- Dashboard for your posts.
- Start private conversations and send/read messages.
- Mobile-responsive layouts, empty/loading/error states, form validation, and basic HTML escaping.
- Safety notice and link to official IRCTC.

## Safety and trust

RailConnect is for coordinating travel plans between people. Do not use it to offer, sell, or transfer a reserved railway ticket. Railway and IRCTC rules can change; users must check official rules and use official channels for bookings. Do not post PNRs, booking references, passwords, phone numbers, identity documents, or sensitive personal information. Treat new contacts as strangers and use caution when arranging to meet.

## Important limitations / not yet complete

- A Supabase project must be created and connected by the owner; until `config.js` is configured, the site intentionally shows setup messaging and no fake listings.
- This is a first-release MVP, not a fully audited production service. Before broad public promotion, add abuse reporting/admin moderation, stronger anti-spam/rate limiting, a privacy policy and terms tailored to your jurisdiction, and an operational process for user reports.
- No independent live train timetable, seat availability, PNR verification, booking, payments, or ticket transfer.
- GitHub Pages deployment is not confirmed by this repository change alone.

## Deployment

The workflow at `.github/workflows/pages.yml` publishes the root site to GitHub Pages on pushes to `main`, provided Pages is configured to use GitHub Actions.
