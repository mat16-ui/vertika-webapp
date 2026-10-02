-- Vertika — nickname migration
-- Run once in: Supabase dashboard → SQL Editor → New query → paste → Run.
-- Adds: nickname uniqueness (case-insensitive) + a 7-day cooldown between changes.
-- Nickname = the existing profiles.display_name column.

-- track when the nickname was last changed
alter table public.profiles
  add column if not exists nickname_changed_at timestamptz;

-- stop auto-filling display_name from the email on signup — the signup form
-- now sets it explicitly right after sb.auth.signUp()
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id) values (new.id);
  return new;
end;
$$ language plpgsql security definer;

-- case-insensitive uniqueness on nicknames (nulls allowed, for the brief
-- moment between auth.signUp() and the follow-up profile update)
create unique index if not exists profiles_display_name_lower_idx
  on public.profiles (lower(display_name))
  where display_name is not null;

-- reject a nickname change made less than 7 days after the last one
create or replace function public.enforce_nickname_cooldown()
returns trigger as $$
begin
  if new.display_name is distinct from old.display_name then
    if old.nickname_changed_at is not null
       and now() - old.nickname_changed_at < interval '7 days' then
      raise exception 'You can only change your nickname once every 7 days.';
    end if;
    new.nickname_changed_at := now();
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists on_profile_nickname_change on public.profiles;
create trigger on_profile_nickname_change
  before update on public.profiles
  for each row execute procedure public.enforce_nickname_cooldown();
