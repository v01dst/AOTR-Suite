# AOTR Suite — Attack on Titan: Revolution

سكربت أتمتة (executor) للعبة **Attack on Titan: Revolution** على Roblox.
مبني **فوق** سكريبت **Tekkit Hub** الموجود أصلاً: نفس مخطط الإعدادات
(`_G.TekkitConfig`)، نفس اصطلاح نداءات السيرفر، ونفس مكتبة الواجهة
(**Rayfield**) — مع إعادة كتابة المنطق بشكل نظيف وقابل للصيانة.

> A Roblox automation suite for *Attack on Titan: Revolution*, built on top of
> the existing **Tekkit Hub** script (same config schema, same server call
> convention, same UI library) with a clean, testable rewrite of the logic.

---

## 1. التشغيل / Usage

### الروابط المنشورة

| الملف | الرابط | الحجم |
|---|---|---|
| **standalone (موصى به)** | `https://raw.githubusercontent.com/v01dst/AOTR-Suite/main/dist/AOTR-standalone.lua` | 158 KB |
| النسخة الكاملة (Rayfield) | `https://raw.githubusercontent.com/v01dst/AOTR-Suite/main/dist/AOTR.lua` | 352 KB |
| اللودر | `https://raw.githubusercontent.com/v01dst/AOTR-Suite/main/dist/loader.lua` | 11 KB |
| المستودع | `https://github.com/v01dst/AOTR-Suite` | — |

```lua
-- الأسهل: النسخة standalone، مفيش أي مكتبة خارجية
loadstring(game:HttpGet("https://raw.githubusercontent.com/v01dst/AOTR-Suite/main/dist/AOTR-standalone.lua"))()
```

> **ليه standalone؟** Rayfield بيحمّل نافذته من Roblox asset عبر
> `game:GetObjects("rbxassetid://...")`، وكتير الـ executors (منهم Xeno)
> بتحجبها فبيسقط. النسخة standalone مبنية بـ `Instance.new` بس وبتشتغل في أي
> executor. لو الـ executor سمح بـ `GetObjects`، النسخة الكاملة هي الأحلى شكلاً.

### الطريقة الأولى: اللودر (مع تشخيص على الشاشة)

انسخ `dist/loader.lua` والصقه في الـ executor. اللودر يرسم نافذة صغيرة
تعرض كل محاولة تحميل بالتفصيل، لأن بعض الـ executors بتبلع `print`:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/v01dst/AOTR-Suite/main/dist/loader.lua"))()
```

اللودر يبحث بالترتيب: `game:HttpGet` ← `game.HttpGet` ← كل اسم معروف لـ
http client في الـ executors ← ملف `AOTR.lua` في مجلد الـ executor. وبيرفض
أي محتوى مش السكربت (فحص العلامة) بدل ما يصرّف صفحة خطأ HTML.

### الطريقة الثانية: تشغيل مباشر

1. افتح اللعبة `Attack on Titan: Revolution` (GameId `4658598196`).
2. الصق محتوى `dist/AOTR-standalone.lua` في الـ executor ونفّذه.
3. الواجهة تفتح تلقائياً. تبويب **Config** لحفظ وإدارة البروفايلات، وتبويب
   **Diagnostics** يعرض حالة التشغيل والأخطاء.

للتشغيل بملف إعدادات خارجي (متوافق مع Tekkit Hub):

```lua
getgenv().TekkitConfig = {
    AutoFarm = true,
    FarmMethod = "Blade",      -- "Blade" | "Hover" | "Teleport"
    AutoStart = true,
    AutoStartMap = "Shiganshina",
    AutoStartDifficulty = "Hardest (w/ Freedom)",
    ItemtoBuyWith = "Pumpkins", -- "Canes" | "Gems" | "Pumpkins"
    Boosts = { "2x Gold Boost [2h]" },
    Webhook = true,
    WebhookLink = "https://discord.com/api/webhooks/...",
}
loadstring(readfile("AOTR.lua"))()
```

الجدول الخارجي يُدمج فوق القيم الافتراضية تلقائياً عند الإقلاع.
اللودر يمنع التشغيل المزدوج، والسكربت نفسه فيه حماية ثانية
(`getgenv().AOTRSuite.Running`).

---

## 2. تغطية قائمة v0276 / Feature coverage

| المطلوب | الحالة | التنفيذ |
|---|---|---|
| Auto Farm Titans (Hover + Blade معاد تصميمهما) | ✅ | `src/Features/Farm.lua` — ثلاث طرق: `Blade` / `Hover` / `Teleport` |
| Teleport Titans | ✅ | `Farm.lua` (`TeleportTitans` + `FarmMethod = "Teleport"`) |
| Inf Spears | ✅ | `src/Features/Combat.lua` — إعادة تعبئة الذخيرة قبل كل رشقة |
| Auto Reload (ينتقل إلى محطة التزود) | ✅ | `src/Features/Reload.lua` |
| اختيار **أأمن** محطة | ✅ | `Reload.pickStation` — الأبعد عن أقرب تيتان |
| Auto Refill | ✅ | `Reload.refillSupplies` + `Remotes.refill()` |
| Damage Extender | ✅ | `Combat.damageScale` — ضرب قيمة الضرر المسجّلة على الـ hitbox |
| Auto Claim Achievements | ✅ | `src/Features/Claim.lua` |
| Auto Claim Daily Reward (**دائم بلا مفتاح**) | ✅ | `Claim.dailyReward` — يُستدعى دائماً في اللوب |
| BoostPurchaseCurrency | ✅ | `src/Features/Boosts.lua` |
| Pumpkins كعملة شراء | ✅ | `ItemtoBuyWith = "Pumpkins"` |
| صعوبة Freedom | ✅ | `Config.DIFFICULTIES` |
| صعوبة Hardest (w/ Freedom) | ✅ | أعلى رتبة (Grade S-) |
| Pumpkins في Player Stats بالويبهوك | ✅ | `src/Stats.lua` + `src/Webhook.lua` |
| Pumpkins في Drops بالويبهوك | ✅ | `Webhook.collectDrops` |
| Auto Load Config | ✅ | `Config.AutoLoad()` |
| Config Selection | ✅ | تبويب Config (قائمة بروفايلات) |
| Minimum Mission Timer = 30 ثانية | ✅ | `Safety.timerAmount()` — حد أدنى صارم |
| "Time Taken" يطابق المؤقت الحقيقي | ✅ | `Safety.elapsed()` يقرأ مؤقت الـ HUD |
| Claim All Quests + Battle Pass | ✅ | `Claim.quests` + `Claim.battlePass` |
| TargetBoss / WavesUpgrades / AutoBuyUpgradesWaves / AutoDieWaves / WaveToDieAt | ✅ | `src/Features/Waves.lua` |
| دعم Kaitun لهذه الميزات | ✅ | حالة الموجة تُعاد بناؤها كل إطار + `Kaitun` في Auto Start |
| Boss Raid المناعي للضرر لا يُضرب | ✅ | `Targets.isImmune` + `Targets.pick` |
| Armored Titan أثناء حراسة القوارب | ✅ | `Targets.isProtectingBoats` |
| Ordinary Titans داخل Colossal Raid | ✅ | `Targets.collectRaidTitans` (بحث أعمق) |
| Low Damage في Colossal Raids | ✅ | تسجيل hitbox لكل هدف + `BossDamage` |
| إصلاح الاستهداف | ✅ | كاش لمسح Workspace + إعادة اختيار عند موت الهدف |
| كشف Shadow Ban | ✅ | `src/Features/ShadowBan.lua` (3 إشارات مستقلة) |
| إصلاح تكرار/فوضى ملفات الإعداد | ✅ | مجلد واحد + بروفايل لكل ملف + تطبيع الأسماء |
| إصلاح سباق القراءة | ✅ | `Config.loadProfile` — single-flight + عدّاد جيل |
| إصلاح عدم حفظ تبويب Config | ✅ | حفظ مؤجّل + أزرار حفظ/إعادة تحميل/حذف |

---

## 3. بنية المشروع / Project layout

```
C:\AOTR-Script\
├─ dist\AOTR.lua              # البناء النهائي (ما يُلصق في الـ executor)
├─ dist\loader.lua            # لودر loadstring (URL ثم ملف محلي)
├─ dist\loadstring-snippets.txt # كل صيغ loadstring جاهزة
├─ src\                       # المصادر (مقاسّة)
│  ├─ main.lua                # نقطة الدخول: يبني Ctx ويشغّل اللوبات
│  ├─ Loader.lua              # منطق اللودر (dist\loader.lua يُولَّد منه)
│  ├─ Config.lua              # المخطط + متجر البروفايلات
│  ├─ Remotes.lua             # الوصول لواجهة السيرفر POST/GET
│  ├─ GameUI.lua              # مسارات واجهة اللعبة + البحث بالكلمات
│  ├─ Targets.lua             # اكتشاف التيتان والتصنيف واستبعاد المستثنى
│  ├─ Stats.lua               # العملات (Gems, Canes, Pumpkins, ...)
│  ├─ Safety.lua              # مؤقت الأمان
│  ├─ Webhook.lua             # تقارير Discord
│  ├─ Util.lua                # أدوات مشتركة
│  ├─ Hub.lua                 # بناء الواجهة
│  └─ Features\               # Farm, Combat, Reload, Claim, Boosts,
│                             # AutoStart, Waves, ShadowBan
├─ vendor\                    # Rayfield (Sirius Software Ltd, Apache-2.0)
├─ tools\                     # build.ps1, check.ps1, test.lua, luau\
└─ upstream\                  # مراجع البحث (غير منشورة في المستودع)
```

### أوامر التطوير

```powershell
powershell -ExecutionPolicy Bypass -File tools\build.ps1   # بناء dist (4 ملفات)
powershell -ExecutionPolicy Bypass -File tools\check.ps1    # فحص الصياغة + توصيل الوحدات + الحزمة
tools\luau\luau.exe tools\test.lua                          # 91 اختبار
```

**مهم:** الاختبارات تشمل تشغيل **الحزمة الحقيقية** (`dist/AOTR.mod.lua`) تحت
محاكي لـ Roblox API (`tools/robloxmock.lua`)، عشان الأخطاء اللي بتحصل جوه
اللعبة بس (زي `TextLabel` مالهاوش حدث `InputBegan`) تتكشّف قبل النشر.

---

## 4. نظام الإعدادات / Config system

* مجلد واحد: `AOTRSuite/configs/<profile>.json` + `AOTRSuite/active.txt`.
* البروفايل يتعرف عليه باسم **مطبّع** (`farm one` = `FarmOne`)، فلا تتكرر
  الملفات ولا تتناثر في مجلدات مختلفة.
* الكتابة **ذرّية**: تُكتب ملفاً مؤقتاً ثم تُستبدل، فلا يتبقّى ملف ناقص.
* القراءة **single-flight**: أي قراءة تبدأ أثناء قراءة أخرى تُنتظر بدل
  التنافس (إصلاح سباق القراءة).
* الحفظ مؤجّل 1.5 ثانية بعد آخر تعديل، فسحب السلايدر لا يكتب 100 ملف.

---

## 5. ما تم التحقق منه من داخل اللعبة / Verified game internals

بُنيت الوحدات على هذه الحقائق (من سكريبتات AOTR متاحة علناً + كود Tekkit Hub):

**الـ Remotes** — `ReplicatedStorage.Assets.Remotes.POST` (و`GET`):

```lua
POST:FireServer("Attacks", "Slash", true)
POST:FireServer("Attacks", "Slash_Release")
POST:FireServer("Attacks", "M1")
POST:FireServer("Hitboxes", "Register", <BasePart>, <damage>, <crit>)
POST:FireServer("S_Equipment", "Spears", "Fire", <Vector3>)
POST:FireServer("Attacks", "Spears", <Vector3>)
POST:FireServer("S_Equipment", "Refill")   -- Equipment / Character / Attacks
```

**التيتان** — `workspace.Titans`، والـ hitbox في `Hitboxes.Hit.Nape`
(أو `Hitboxes.Nape`، أو أي جزء باسم `nape`/`weakpoint`/`core`).

**واجهة اللعبة**

```
PlayerGui.Interface
  .Title_Screen.Slots.<A-D>.Select_<A-D>     .Title_Screen.Buttons.Play
  .Warning.Prompt.Main.No
  .Missions.Prompt.Selection.Missions
  .Missions.Missions.Main.Maps.Maps.<Map>_Missions
  .Missions.Missions.Main.Info.Main.Buttons.Creation_Missions
  .Missions.Info.Main.Info.Modifiers.Modifiers_Buttons
  .Missions.Info.Main.Info.Modifiers.Options.<Modifier>
  .Missions.Info.Main.Info.Main.Info_Buttons.Begin
  .Rewards.Main.Info.Main.Buttons.Retry | Leave_2
  .HUD.Main.Top["7"].Blades.Inner.Bar.Gradient
  .HUD.Main.Top["7"].Gas.Inner.Bar.Gradient
```

الخرائط: `Chapel, Docks, Forest, Outskirts, Shiganshina, Stohess, Trost, Utgard`.
الصعوبات: `Easy, Normal, Hard, Severe, Aberrant, Freedom` + `Hardest (w/ Freedom)`.

> ملاحظة: كل ما يخص واجهة اللعبة يُبحث **بالكلمات** (اسم الزر/نصّه) مع
> مسار مباشر كخطة أول، فإذا غيّرت اللعبة مساراتها لا يتعطّل السكربت.
> نداءات السيرفر تُخزَّن "المحرك" على شكل مرشّحات (`Remotes.postAny`)،
> وأول صيغة تنجح تُحفظ للجلسة القادمة.

---

## 6. حدود معروفة / Known limitations

* نداءات السيرفر أعلاه مأخوذة من سكريبتات منشورة؛ إن غيّر المطوّر
  أسماء الـ categories، ستتوقف بعض الميزات حتى تُحدَّث (`src/Remotes.lua`).
* **Auto Claim / Daily Reward / BoostPurchaseCurrency** تعمل بالضغط على
  أزرار الواجهة، لا بــ remote — لذلك تعمل فقط داخل اللوبي (المكافآت
  تُمنح في اللوبي). خيار `ItemtoBuyWith` يحتاج فتح المتجر يدوياً مرة
  واحدة حتى تظهر خيارات العملة.
* **Safety Timer** يعتمد على مؤقت الـ HUD؛ إن أخفت اللعبة المؤقت يُستخدم
  قياس زمني بديل (والمؤقت يبقى 30 ثانية على الأقل).
* السكربت يحتاج executor يدعم: `writefile/readfile` (اختياري للحفظ)،
  `VirtualInputManager` (الضغط على أزرار اللعبة)، `http.request`
  (اختياري للويبهوك).

---

## 7. المصادر / Sources

| المصدر | الاستخدام |
|---|---|
| `zerunquist/tekkithub` | Tekkit Hub — مخطط `TekkitConfig` |
| `quoc12092008/Chui1209` | جدول إعدادات Tekkit كامل |
| `Haianhdrso1/vps` | بروتوكول `POST`/`GET` وبنية التيتان |
| `JustLevel/working-newbie` | مراجع AOTR إضافية |
| `SiriusSoftwareLtd/Rayfield` | واجهة المستخدم (Apache-2.0) |
| `CandyFursona/AoT-Script` | مسارات HUD وواجهة المكافآت |

النسخ الأصلية محفوظة في `upstream/` محلياً، وهي **غير منشورة** في هذا
المستودع لأنها مشاريع أخرى.

---

## 8. تنبيه

استخدام سكربتات الـ executor مخالف لشروط Roblox وقد يؤدي حظر الحساب.
استخدم حساباً بديلاً للتجربة. المسؤولية عن استخدامك على عاتقك.
