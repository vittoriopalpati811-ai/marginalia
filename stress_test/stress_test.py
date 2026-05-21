"""
Marginalia Stress Test — 500 concurrent virtual users in 10 minutes.

Each virtual user:
  1. Signs up with a unique email/password
  2. Completes their profile (display_name, optional reading status)
  3. Creates 2-3 posts
  4. Follows 3 random other users
  5. Likes and comments on posts from their feed
  6. Optionally starts a DM conversation

Requirements:
  pip install httpx asyncio

Usage:
  python stress_test.py

Configuration:
  Set SUPABASE_URL and SUPABASE_ANON_KEY below.
  Optionally set SUPABASE_SERVICE_ROLE_KEY to auto-delete test users afterwards.

⚠️  Uses real Supabase resources. Run on the FREE tier only if your quota allows it.
    After the test, delete test users via the Dashboard → Authentication → Users
    (filter by email containing "@stresstest.marginalia.dev").
"""

import asyncio
import random
import string
import time
import json
import sys
from dataclasses import dataclass, field
from typing import Optional

try:
    import httpx
except ImportError:
    print("❌  httpx not installed. Run: pip install httpx")
    sys.exit(1)

# ─── CONFIGURATION ────────────────────────────────────────────────────────────

SUPABASE_URL      = "https://ibucvloawkfwobaelwbr.supabase.co"
SUPABASE_ANON_KEY = (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
    "eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlidWN2bG9hd2tmd29iYWVsd2JyIiwicm9sZSI6"
    "ImFub24iLCJpYXQiOjE3Nzg0NDA0NDAsImV4cCI6MjA5NDAxNjQ0MH0."
    "TDjLBCVsjoITyT_GlsVw8fOTfelvL8ld56rTMdBizmc"
)
# Optional: service role key to clean up after test
SUPABASE_SERVICE_ROLE_KEY = ""   # leave empty to skip cleanup

TOTAL_USERS       = 500          # number of virtual users to simulate
SPAWN_OVER_SECS   = 540          # spawn all users within 9 minutes (leave 1 min for wrap-up)
MAX_CONCURRENCY   = 80           # max simultaneous HTTP connections
TEST_EMAIL_DOMAIN = "@stresstest.marginalia.dev"

# Sample content for realism
_BOOKS = [
    ("Il nome della rosa", "Umberto Eco"),
    ("1984", "George Orwell"),
    ("Se questo è un uomo", "Primo Levi"),
    ("Siddharta", "Hermann Hesse"),
    ("Cent'anni di solitudine", "Gabriel García Márquez"),
    ("L'alchimista", "Paulo Coelho"),
    ("Il signore degli anelli", "J.R.R. Tolkien"),
    ("Anna Karenina", "Lev Tolstoj"),
    ("Delitto e castigo", "Fëdor Dostoevskij"),
    ("Il processo", "Franz Kafka"),
    ("Dune", "Frank Herbert"),
    ("Sapiens", "Yuval Noah Harari"),
    ("Thinking, Fast and Slow", "Daniel Kahneman"),
    ("Atomic Habits", "James Clear"),
    ("The Pragmatic Programmer", "David Thomas"),
]

_POST_BODIES = [
    "Ho appena finito un capitolo stupendo. Certe pagine rimangono dentro per sempre.",
    "Leggere è il miglior modo di viaggiare senza muoversi.",
    "Questo libro mi ha cambiato il modo di vedere le cose.",
    "Una frase bellissima che ho trovato oggi: leggere è resistere.",
    "Torno sempre agli stessi libri come si torna a casa.",
    "Highlight del giorno. Vale più di mille parole.",
    "Chi legge molto capisce il mondo in modo diverso.",
    "Non riesco a smettere. Ancora dieci pagine e poi dormo.",
    "Questo autore scrive come se avesse vissuto mille vite.",
    "Finalmente ho tempo di leggere. E che lettura!",
    "Un libro mi segue ovunque. Stavolta è davvero speciale.",
    "Pagina 200 e ancora non riesco a staccarmi.",
    "Certi libri ti capiscono meglio di quanto tu capisca te stesso.",
    "La mia libreria è un caos. Un caos bellissimo.",
    "Ogni sera un capitolo. Ogni mattina un po' più ricco.",
]

_NAMES = [
    "Giulia", "Marco", "Sara", "Luca", "Alice", "Matteo", "Emma", "Davide",
    "Chiara", "Francesco", "Valentina", "Andrea", "Sofia", "Lorenzo", "Martina",
    "Simone", "Elena", "Riccardo", "Federica", "Alessandro", "Beatrice", "Filippo",
    "Elisa", "Nicola", "Claudia", "Giorgio", "Alessia", "Pietro", "Silvia", "Daniele",
]

# ─── DATA CLASSES ─────────────────────────────────────────────────────────────

@dataclass
class VirtualUser:
    user_id: int
    email: str
    password: str
    display_name: str
    token: str = ""
    uid: str = ""
    post_ids: list = field(default_factory=list)
    error: str = ""
    completed_steps: list = field(default_factory=list)


@dataclass
class StressStats:
    signups_ok: int = 0
    signups_fail: int = 0
    posts_ok: int = 0
    follows_ok: int = 0
    likes_ok: int = 0
    comments_ok: int = 0
    dms_ok: int = 0
    errors: list = field(default_factory=list)
    start_time: float = field(default_factory=time.time)

    def report(self) -> str:
        elapsed = time.time() - self.start_time
        return (
            f"\n{'='*50}\n"
            f"  MARGINALIA STRESS TEST RESULTS\n"
            f"{'='*50}\n"
            f"  Duration:      {elapsed:.0f}s\n"
            f"  Signups:       {self.signups_ok} ✅  {self.signups_fail} ❌\n"
            f"  Posts created: {self.posts_ok}\n"
            f"  Follows:       {self.follows_ok}\n"
            f"  Likes:         {self.likes_ok}\n"
            f"  Comments:      {self.comments_ok}\n"
            f"  DM convs:      {self.dms_ok}\n"
            f"  Errors (top5): {self.errors[:5]}\n"
            f"{'='*50}\n"
        )


# ─── SUPABASE HTTP HELPERS ───────────────────────────────────────────────────

def _rest_url(path: str) -> str:
    return f"{SUPABASE_URL}/rest/v1/{path}"

def _auth_url(path: str) -> str:
    return f"{SUPABASE_URL}/auth/v1/{path}"

def _rpc_url(fn: str) -> str:
    return f"{SUPABASE_URL}/rest/v1/rpc/{fn}"

def _anon_headers() -> dict:
    return {
        "apikey": SUPABASE_ANON_KEY,
        "Content-Type": "application/json",
    }

def _auth_headers(token: str) -> dict:
    return {
        "apikey": SUPABASE_ANON_KEY,
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }


# ─── VIRTUAL USER LIFECYCLE ───────────────────────────────────────────────────

async def run_user(
    client: httpx.AsyncClient,
    user: VirtualUser,
    all_users: list,
    stats: StressStats,
    sem: asyncio.Semaphore,
):
    async with sem:
        # ── 1. Sign up ────────────────────────────────────────────────────────
        try:
            r = await client.post(
                _auth_url("signup"),
                headers=_anon_headers(),
                json={"email": user.email, "password": user.password},
                timeout=15,
            )
            if r.status_code in (200, 201):
                data = r.json()
                user.token = data.get("access_token", "")
                user.uid = data.get("user", {}).get("id", "")
                stats.signups_ok += 1
                user.completed_steps.append("signup")
            else:
                stats.signups_fail += 1
                user.error = f"signup {r.status_code}: {r.text[:120]}"
                stats.errors.append(user.error)
                return
        except Exception as e:
            stats.signups_fail += 1
            user.error = f"signup exc: {e}"
            stats.errors.append(user.error)
            return

        if not user.token:
            # Email confirmation required — can't continue without a session
            stats.signups_fail += 1
            return

        h = _auth_headers(user.token)

        # ── 2. Update profile ─────────────────────────────────────────────────
        try:
            book = random.choice(_BOOKS)
            payload = {
                "id": user.uid,
                "display_name": user.display_name,
                "currently_reading_title": book[0],
                "currently_reading_author": book[1],
            }
            await client.post(
                _rest_url("profiles"),
                headers={**h, "Prefer": "resolution=merge-duplicates"},
                json=payload,
                timeout=10,
            )
            user.completed_steps.append("profile")
        except Exception:
            pass

        # ── 3. Create 2-3 posts ───────────────────────────────────────────────
        num_posts = random.randint(2, 3)
        for _ in range(num_posts):
            try:
                body = random.choice(_POST_BODIES)
                r = await client.post(
                    _rest_url("posts"),
                    headers=h,
                    json={"user_id": user.uid, "body": body},
                    timeout=10,
                )
                if r.status_code in (200, 201):
                    created = r.json()
                    pid = created[0]["id"] if isinstance(created, list) else created.get("id")
                    if pid:
                        user.post_ids.append(pid)
                    stats.posts_ok += 1
            except Exception:
                pass

        await asyncio.sleep(random.uniform(0.2, 1.0))

        # ── 4. Follow 3 random other users ───────────────────────────────────
        others = [u for u in all_users if u.uid and u.uid != user.uid][:20]
        to_follow = random.sample(others, min(3, len(others)))
        for target in to_follow:
            try:
                r = await client.post(
                    _rest_url("follows"),
                    headers={**h, "Prefer": "resolution=merge-duplicates"},
                    json={"follower_id": user.uid, "following_id": target.uid},
                    timeout=8,
                )
                if r.status_code in (200, 201):
                    stats.follows_ok += 1
            except Exception:
                pass

        await asyncio.sleep(random.uniform(0.1, 0.5))

        # ── 5. Like + comment on posts ────────────────────────────────────────
        # Collect some post IDs from followed users
        sample_post_ids = []
        for u in to_follow:
            sample_post_ids.extend(u.post_ids)
        random.shuffle(sample_post_ids)
        sample_post_ids = sample_post_ids[:3]

        for pid in sample_post_ids:
            # Like
            try:
                r = await client.post(
                    _rest_url("post_likes"),
                    headers={**h, "Prefer": "resolution=merge-duplicates"},
                    json={"post_id": pid, "user_id": user.uid},
                    timeout=8,
                )
                if r.status_code in (200, 201):
                    stats.likes_ok += 1
            except Exception:
                pass

            # Comment (50% chance)
            if random.random() < 0.5:
                try:
                    comment = random.choice([
                        "Bellissima citazione!",
                        "Anch'io ho letto questo libro.",
                        "Condivido al 100%.",
                        "Devo assolutamente leggerlo.",
                        "Uno dei miei preferiti!",
                    ])
                    r = await client.post(
                        _rest_url("post_comments"),
                        headers=h,
                        json={"post_id": pid, "user_id": user.uid, "content": comment},
                        timeout=8,
                    )
                    if r.status_code in (200, 201):
                        stats.comments_ok += 1
                except Exception:
                    pass

        await asyncio.sleep(random.uniform(0.1, 0.4))

        # ── 6. Start a DM (30% chance) ────────────────────────────────────────
        if random.random() < 0.3 and to_follow:
            dm_target = random.choice(to_follow)
            if dm_target.uid:
                try:
                    r = await client.post(
                        _rpc_url("create_direct_conversation"),
                        headers=h,
                        json={"p_other_user_id": dm_target.uid},
                        timeout=10,
                    )
                    if r.status_code in (200, 201):
                        conv_id = r.json()
                        if conv_id:
                            # Send a message
                            await client.post(
                                _rest_url("messages"),
                                headers=h,
                                json={
                                    "conversation_id": conv_id,
                                    "sender_id": user.uid,
                                    "content": "Ciao! Anche tu ami i libri?",
                                },
                                timeout=8,
                            )
                            stats.dms_ok += 1
                except Exception:
                    pass

        user.completed_steps.append("done")


# ─── CLEANUP ─────────────────────────────────────────────────────────────────

async def cleanup_test_users(client: httpx.AsyncClient, user_ids: list):
    if not SUPABASE_SERVICE_ROLE_KEY:
        print(
            "\n📋 Cleanup skipped (no SERVICE_ROLE_KEY). "
            "Delete test users manually:\n"
            "   Supabase Dashboard → Authentication → Users → "
            f"filter email contains '{TEST_EMAIL_DOMAIN}'"
        )
        return

    print(f"\n🧹 Deleting {len(user_ids)} test users…")
    svc_headers = {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SUPABASE_SERVICE_ROLE_KEY}",
        "Content-Type": "application/json",
    }
    deleted = 0
    for uid in user_ids:
        try:
            r = await client.delete(
                f"{SUPABASE_URL}/auth/v1/admin/users/{uid}",
                headers=svc_headers,
                timeout=10,
            )
            if r.status_code in (200, 204):
                deleted += 1
        except Exception:
            pass
    print(f"   ✅ Deleted {deleted}/{len(user_ids)} users")


# ─── MAIN ─────────────────────────────────────────────────────────────────────

async def main():
    print(f"🚀 Marginalia Stress Test — {TOTAL_USERS} users over {SPAWN_OVER_SECS}s")
    print(f"   Supabase: {SUPABASE_URL}")
    print(f"   Max concurrency: {MAX_CONCURRENCY}\n")

    stats = StressStats()
    sem = asyncio.Semaphore(MAX_CONCURRENCY)

    # Pre-generate user objects
    users: list[VirtualUser] = []
    for i in range(TOTAL_USERS):
        suffix = ''.join(random.choices(string.ascii_lowercase + string.digits, k=8))
        users.append(VirtualUser(
            user_id=i,
            email=f"user_{i}_{suffix}{TEST_EMAIL_DOMAIN}",
            password=f"StressT3st!{suffix}",
            display_name=f"{random.choice(_NAMES)}{random.randint(1, 999)}",
        ))

    # Stagger task creation to spread load evenly over SPAWN_OVER_SECS
    delay_per_user = SPAWN_OVER_SECS / TOTAL_USERS

    async with httpx.AsyncClient(
        limits=httpx.Limits(max_connections=MAX_CONCURRENCY + 20, max_keepalive_connections=MAX_CONCURRENCY),
        timeout=httpx.Timeout(20),
    ) as client:
        tasks = []
        for i, user in enumerate(users):
            # Stagger spawning
            await asyncio.sleep(delay_per_user * random.uniform(0.8, 1.2))
            t = asyncio.create_task(
                run_user(client, user, users[:i], stats, sem)  # only users spawned so far are "others"
            )
            tasks.append(t)

            # Progress report every 50 users
            if (i + 1) % 50 == 0:
                elapsed = time.time() - stats.start_time
                print(
                    f"   [{elapsed:5.0f}s] Spawned {i+1}/{TOTAL_USERS} users | "
                    f"signups: {stats.signups_ok} ✅ {stats.signups_fail} ❌ | "
                    f"posts: {stats.posts_ok}"
                )

        print(f"\n⏳ All users spawned. Waiting for tasks to complete…")
        await asyncio.gather(*tasks, return_exceptions=True)

        # Cleanup
        completed_uids = [u.uid for u in users if u.uid]
        await cleanup_test_users(client, completed_uids)

    print(stats.report())


if __name__ == "__main__":
    asyncio.run(main())
