# 0001: Run the AI endpoints as a Python service

- **Status:** accepted
- **Date:** 2026-11-07

## Context

The MVP spec puts `parse` (and later `assistant`, `insights` and `daily-brief`) in Supabase Edge Functions. Edge Functions run only TypeScript on Deno. We want the backend in Python, and Gemini as the model instead of Claude.

## Decision

The AI endpoints live in `backend/api`, a FastAPI service that calls Gemini (`gemini-3.8-flash` by default) with Google's official `google-genai` Python SDK, using a JSON response schema. It serves the same contract the clients already expect: `POST /parse` with snake_case JSON.

Supabase stays the plan for Postgres, Row Level Security, Auth and Storage. The service will verify Supabase JWTs and write `ai_captures` with the service role once sign-in lands.

## Consequences

- The service needs its own host (for example Fly.io, Render, Railway or Cloud Run), with `GEMINI_API_KEY` stored in that host's secrets.
- The recurrence validator is written in Python (`sorted_api/rrule.py`) and must stay in step with `RecurrenceRule.swift`. Both sides run the same test cases.
- The client setting `SORTED_FUNCTIONS_URL` now points at this service's base URL.
