# TextChat

A text-only messenger (no calls) built with Flutter + Supabase.
Email/password sign up and login, real-time 1-to-1 text chats, chat list, password reset.

The Supabase project is already set up (tables `tc_profiles`, `tc_chats`,
`tc_messages`, row-level security, realtime). `supabase/schema.sql` is a copy of
what was applied, in case you ever need to recreate it in another project.

## Before first use (one setting)

Supabase dashboard → **Authentication → Sign In / Providers → Email**:
- Leave **Confirm email** ON for real use (users must click a link in their inbox).
  The free built-in email sender has a low hourly limit.
- Or turn it OFF while testing so sign-up logs in immediately.

## Put it on GitHub and release the APK

```bash
git init
git add .
git commit -m "TextChat first version"
git branch -M main
git remote add origin https://github.com/cr07thegoat2025-cloud/Secret.git
git push -u origin main

git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions then builds the APK and attaches `app-release.apk` to a new
**Release** (repo → Releases). You can also run it manually from the Actions tab
(the APK then appears as a downloadable artifact on that run).

Note: if the repo is private, the Release (and APK) is only visible to people with
access to the repo. Make it public to share the download link.

Install on a phone: download the APK, allow "install unknown apps", open it.

## Features

- Each message shows how long ago it was sent; your messages also show "Seen 3 min ago" once the other person has opened the chat.
- Send photos and videos from the paperclip button (up to 50 MB each). Files are private to the two people in the chat.

## Notes

- The Supabase URL and publishable key in `lib/main.dart` are public-by-design
  client values. Never put the `service_role` key in the app.
- The APK is signed with Flutter's debug key: fine for sharing/testing, not for the Play Store.
- To start a chat, tap the button and enter another registered user's email.
- Free Supabase projects pause after about a week of inactivity; restore from the dashboard.
- Run locally: `flutter create --platforms=android . && flutter run`
