-- Lets a user delete their own account (cascades to all data via FK).
-- Called from the app via supabase.rpc('delete_my_account').
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from auth.users where id = auth.uid();
end;
$$;
