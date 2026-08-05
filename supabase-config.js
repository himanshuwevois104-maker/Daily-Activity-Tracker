/* ------------------------------------------------------------------
   WeVois Daily Activity Tracker - connection settings.

   Paste the two values from your NEW Supabase project:
     Supabase dashboard -> Project Settings -> API
       Project URL   -> url
       anon public   -> anonKey

   The anon key is meant to be public - it is in every browser that loads
   the app. What protects your data is Row Level Security, which
   TRACKER-SETUP.sql switches on for every table. Never put the
   service_role key in this file.
   ------------------------------------------------------------------ */
window.TRACKER_CONFIG = {
  url:     "https://YOUR_PROJECT_REF.supabase.co",
  anonKey: "YOUR_ANON_PUBLIC_KEY"
};
