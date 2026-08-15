-- Public marketing-site content, replacing Netlify CMS.
--
-- Two things live here: news/announcements shown on the public site, and the
-- homepage photo gallery. Both are read at BUILD TIME by Eleventy using the
-- anon key, so both need a policy that lets an unauthenticated reader see the
-- published rows — that is deliberate, this is public marketing content.
--
-- Note this is entirely separate from public.announcements, which is the
-- internal school noticeboard for logged-in staff and students.

create table public.public_announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  -- ASCII-safe and unique: the old Netlify CMS slugged straight off the title,
  -- which produced URLs like /news/🎓-rohi-college-admissions.../
  slug text not null unique,
  category text not null default 'News'
    check (category in ('News', 'Admissions', 'Events', 'Achievements', 'Notices')),
  cover_image_path text,
  cover_image_alt text,
  excerpt text,
  body_html text not null default '',
  status text not null default 'draft' check (status in ('draft', 'published')),
  -- A publish_at in the future means scheduled: it is excluded from reads
  -- until the moment passes.
  publish_at timestamptz not null default now(),
  featured boolean not null default false,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index public_announcements_live_idx
  on public.public_announcements (publish_at desc)
  where status = 'published';

create or replace function public.set_public_announcements_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger public_announcements_updated_at
before update on public.public_announcements
for each row execute function public.set_public_announcements_updated_at();

alter table public.public_announcements enable row level security;

create policy "public announcements admin full access" on public.public_announcements
  for all using (public.is_admin()) with check (public.is_admin());

-- Intentionally open to anon: this is the public website's content, and the
-- static build reads it with the anon key. Drafts and future-dated posts stay
-- invisible.
create policy "public announcements readable when live" on public.public_announcements
  for select using (status = 'published' and publish_at <= now());


-- ---------------------------------------------------------------------------
-- Homepage gallery
-- ---------------------------------------------------------------------------
-- Albums match the existing homepage tabs, kept as-is. Two renditions are
-- stored per photo: the grid slot is ~260px while the lightbox is ~800px, so
-- shipping one large file to both would waste mobile data on the grid.
create table public.site_gallery (
  id uuid primary key default gen_random_uuid(),
  album text not null check (album in ('class-projects', 'cultural-day', 'daily-moments')),
  thumb_path text not null,
  full_path text not null,
  alt_text text,
  sort_order integer not null default 0,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create index site_gallery_album_idx on public.site_gallery (album, sort_order, created_at);

alter table public.site_gallery enable row level security;

create policy "site gallery admin full access" on public.site_gallery
  for all using (public.is_admin()) with check (public.is_admin());

create policy "site gallery public read" on public.site_gallery
  for select using (true);

-- The cap is enforced here rather than only in the admin page: a limit that
-- lives solely in the browser is not a limit.
create or replace function public.enforce_gallery_cap()
returns trigger
language plpgsql
as $$
declare
  current_count integer;
begin
  select count(*) into current_count from public.site_gallery where album = new.album;
  if current_count >= 12 then
    raise exception 'This album already holds the maximum of 12 photos. Remove one before adding another.';
  end if;
  return new;
end;
$$;

create trigger site_gallery_cap
before insert on public.site_gallery
for each row execute function public.enforce_gallery_cap();


-- ---------------------------------------------------------------------------
-- Storage: public bucket for marketing media
-- ---------------------------------------------------------------------------
-- Genuinely public, unlike student-photos. A static build cannot use signed
-- URLs — they expire, and the built HTML would start 404ing days later.
insert into storage.buckets (id, name, public)
values ('site-media', 'site-media', true)
on conflict (id) do nothing;

create policy "site media public read" on storage.objects
  for select using (bucket_id = 'site-media');

create policy "site media admin insert" on storage.objects
  for insert with check (bucket_id = 'site-media' and public.is_admin());

create policy "site media admin update" on storage.objects
  for update using (bucket_id = 'site-media' and public.is_admin())
  with check (bucket_id = 'site-media' and public.is_admin());

create policy "site media admin delete" on storage.objects
  for delete using (bucket_id = 'site-media' and public.is_admin());
