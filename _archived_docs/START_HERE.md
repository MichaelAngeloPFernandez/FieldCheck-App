# ⚡ FieldCheck Quick Reference Card

## Your App Status
- **Current:** 97% complete, blocked by outdated APK
- **Issues:** 6 bugs in old APK, 8+ validation issues, no error handling
- **Goal:** Production-ready in 5-8 hours

---

## 🎯 Do This First (1-2 hours)

### 1. Rebuild APK
```bash
cd field_check
flutter clean && flutter pub get && flutter build apk --release
```

### 2. Fix Report Queries  
**File:** `field_check/lib/services/report_service.dart`
**Change:** Add `?type=attendance` to report endpoint calls

### 3. Fix Export Controller
**File:** `backend/controllers/exportController.js`
**Change:** Map exact MongoDB field names

---

## 🤖 Using Your Agent

```
@fieldcheck-dev [Your request]
```

**Examples:**
- `@fieldcheck-dev Rebuild APK and test it`
- `@fieldcheck-dev Fix the report query issue`
- `@fieldcheck-dev Guide me through Phase 1 of the fixes`

---

## 📋 Three Phases of Fixes

| Phase | Time | What | Status |
|-------|------|------|--------|
| 1 | 1-2h | Unblock app | 🔴 START HERE |
| 2 | 2-3h | Add validation | ⏳ After Phase 1 |
| 3 | 2-3h | Security | ⏳ After Phase 2 |

**Full Plan:** `.github/CRITICAL_FIXES_PLAN.md`

---

## 📚 Key Documentation

- **Main Setup:** `SETUP_COMPLETE.md`
- **All Fixes:** `.github/CRITICAL_FIXES_PLAN.md`
- **Backend Rules:** `.github/instructions/backend.instructions.md`
- **Frontend Rules:** `.github/instructions/frontend.instructions.md`

---

## 🐛 Top Issues to Fix

1. **Reports show 0 results** → Fix query parameter
2. **Export fails** → Fix field names  
3. **APK has old bugs** → Rebuild it
4. **Requests timeout** → Add timeouts
5. **Socket disconnects** → Enable reconnection

---

## ✅ Done!

Your app now has:
- ✨ Custom AI agent
- 📋 Automated code guidelines
- 🎯 Clear fix roadmap
- 🔧 Quality enforcement

**START:** Read `SETUP_COMPLETE.md` and do Phase 1!
