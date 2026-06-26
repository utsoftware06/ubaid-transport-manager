-- UUID support
create extension if not exists "pgcrypto";

-- Addas Table
create table if not exists public.addas (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  city text,
  address text,
  phone text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);