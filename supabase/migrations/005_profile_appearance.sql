-- Marginalia — Migration 005: profile appearance customisation
-- Adds gradient_preset and pattern_preset to profiles table.
-- Run in Supabase SQL Editor. Idempotent.

alter table public.profiles
  add column if not exists gradient_preset text not null default 'sepia',
  add column if not exists pattern_preset  text not null default 'none';
