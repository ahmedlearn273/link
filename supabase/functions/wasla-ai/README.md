# wasla-ai (PRIME)

Deploy: `supabase functions deploy wasla-ai --no-verify-jwt` (the function checks the caller itself; the database rejects anonymous calls).
Requires the P1 SQL (public.prime_answer). Secrets used: SUPABASE_URL and SUPABASE_ANON_KEY (provided automatically).

Switch on an AI model later: set AI_MODEL (constant in index.ts, or a secret), add secrets AI_API_KEY and AI_BASE_URL
(Groq: https://api.groq.com/openai/v1), redeploy. If the model fails or times out, the engine answer is returned.
Rollback: redeploy the previous version from the Supabase dashboard.
