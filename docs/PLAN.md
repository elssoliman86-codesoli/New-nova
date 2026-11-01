# خطة مشروع Nova (Flutter)

تطبيق Android لإدارة المهام والتركيز، بتصميم **Dark Glassmorphism × Dynamic Island × Neumorphism**.

**طريقة قراءة الملف:**
- `[x]` يعني اتعمل واتنشر في الريبو.
- `[ ]` يعني لسه هيتعمل.
- كل ما ملف أو خطوة تخلص، الـ checkbox بتتحدث في نفس الـ commit.

---

## 0. اللي اتكشف وغيّر الخطة

- [x] الريبو كان فاضي تماماً (مفيش branches ولا ملفات)، فالتطبيق بيتبني من الصفر.
- [x] بيئة التنفيذ مفيهاش Flutter ولا Android SDK، والشبكة فيها بتمنع `dl.google.com` و`storage.googleapis.com`.
- [x] القرار: الـ APK بيتبني على GitHub Actions، وبيتنشر كـ Release في الريبو.
- [x] تنبيه: أول compile حقيقي للكود هيحصل على GitHub Actions، لأن مفيش compiler محلي.

## 1. القرارات

| البند | القرار |
|---|---|
| التقنية | Flutter (stable) |
| فكرة التطبيق | Nova: Tasks + Focus Timer + Insights |
| الـ Auth | محلي على الجهاز (مفيش backend)، وجاهز للربط بـ API من `app_store.dart` |
| المكتبات | `shared_preferences` فقط |
| الخط | Inter، بيتحمّل في الـ CI |
| لغة الواجهة | إنجليزي |
| توقيع الـ APK | debug key (يكفي للتثبيت المباشر، ولـ Play Store محتاج keystore خاص) |

---

## 2. شجرة الملفات

```text
new-nova/
├─ .github/workflows/build-apk.yml
├─ .gitignore
├─ README.md
├─ docs/PLAN.md
├─ pubspec.yaml
├─ analysis_options.yaml
├─ tool/get_fonts.sh
├─ tool/patch_android.sh
├─ assets/fonts/                  (Inter، بيتحمّل في CI)
├─ test/widget_test.dart
└─ lib/
   ├─ main.dart
   ├─ app.dart
   ├─ core/
   │  ├─ tokens.dart
   │  ├─ theme.dart
   │  ├─ motion.dart
   │  ├─ ui_prefs.dart
   │  ├─ haptics.dart
   │  └─ formatters.dart
   ├─ data/
   │  ├─ models.dart
   │  ├─ storage.dart
   │  ├─ app_store.dart
   │  └─ app_scope.dart
   ├─ ui/
   │  ├─ background.dart
   │  ├─ glass.dart
   │  ├─ neu.dart
   │  ├─ island.dart
   │  ├─ floating_nav.dart
   │  ├─ components.dart
   │  ├─ charts.dart
   │  ├─ states.dart
   │  └─ overlays.dart
   └─ screens/
      ├─ boot_screen.dart
      ├─ auth_screen.dart
      ├─ shell_screen.dart
      ├─ home_screen.dart
      ├─ tasks_screen.dart
      ├─ task_detail_screen.dart
      ├─ task_editor_sheet.dart
      ├─ focus_sheet.dart
      ├─ insights_screen.dart
      ├─ profile_screen.dart
      ├─ settings_screen.dart
      └─ notifications_screen.dart
```

مجلد `android/` بيتولّد بـ `flutter create` داخل الـ CI (ولو بتبني محلي، شغّل نفس الأمر مرة واحدة).

---

## 3. خطوات التنفيذ بالترتيب

### الخطوة 1: الأساس (Project skeleton)

- [x] `pubspec.yaml`: اسم المشروع `nova`، المكتبة الوحيدة `shared_preferences`، تعريف خط Inter.
- [x] `analysis_options.yaml`: قواعد lints الأساسية.
- [x] `.gitignore`: ملفات Flutter وAndroid المولّدة.
- [x] `README.md`: أوامر البناء والتشغيل وطريقة تنزيل الـ APK.
- [x] `tool/get_fonts.sh` (إضافة على الخطة): بيحمّل خط Inter، والـ CI وأنت محلياً بتستخدموه.
- [x] `lib/main.dart` و`test/widget_test.dart` **مؤقتين** عشان أتأكد إن الـ pipeline شغال (هيتبدلوا في الخطوتين 6 و7).

### الخطوة 2: نظام التصميم (`lib/core/`)

- [ ] `tokens.dart`
  - `NovaColors`: `#080D19` و`#0D1525` و`#398BFF` و`#42C8FF` و`#F2F6FF` و`#8C9BB5` + ألوان حالات هادية.
  - `NovaSpace`: 4/8/12/16/20/24/32.
  - `NovaRadius`: sm/md/lg/xl/pill.
  - `NovaType`: سلم الخطوط (title وheadline وbody وcaption).
  - `NovaShadows`: raised وpressed.
- [ ] `theme.dart`: `buildNovaTheme()` يرجّع `ThemeData` داكن بالخط والألوان وtransitions الصفحات.
- [ ] `motion.dart`
  - `NovaSpring`: ثوابت الـ spring.
  - `NovaPageRoute`: انتقال fade + scale خفيف، ويحترم reduce motion.
  - `Pressable`: ويدجت بيصغّر 0.96 عند الضغط.
- [ ] `ui_prefs.dart` (إضافة على الخطة): `UiPrefs` ويدجت بيوصّل إعدادات reduce blur وreduce motion للواجهة من غير ما كل الشاشات تتبني تاني.
- [ ] `haptics.dart`: `Haptics.tap()` و`select()` و`success()`، وكلهم بيتأكدوا من إعداد الـ haptics.
- [ ] `formatters.dart`: `formatTimer(Duration)` و`formatDue(DateTime)` و`greetingFor(DateTime)`.

### الخطوة 3: البيانات والحالة (`lib/data/`)

- [ ] `models.dart`
  - `Priority` (low/medium/high).
  - `TaskItem`: id وtitle وnotes وpriority وdue وdone وcreatedAt وcompletedAt، مع `toJson` و`fromJson` و`copyWith`.
  - `FocusLog` و`NovaNotification` و`UserProfile` و`AppSettings`.
- [ ] `storage.dart`: `Storage.read(key)` و`write(key, json)` فوق `shared_preferences`، مع fallback في الذاكرة لو فشل.
- [ ] `app_store.dart`: `AppStore extends ChangeNotifier`، قلب التطبيق.
  - جلسة المستخدم: `init()` و`signIn()` و`signUp()` و`signOut()`.
  - المهام: `addTask()` و`updateTask()` و`toggleTask()` و`deleteTask()` و`undoDelete()`.
  - القراءة المشتقة: `todayTasks` و`openTasks` و`streak` و`focusMinutesLast7Days()`.
  - التركيز: `startFocus(minutes, taskId)` و`pauseFocus()` و`resumeFocus()` و`stopFocus()`. فيه `Timer.periodic` كل ثانية، وبيشتغل **بس** وقت الجلسة.
  - الإشعارات: `pushNotification()` و`markAllRead()` و`clearNotifications()`.
  - الإعدادات: `setHaptics()` و`setIsland()` و`setReduceBlur()` و`setReduceMotion()` و`setDailyGoal()`.
  - الحفظ: `_persist()` بتحفظ بعد 300 ملي ثانية من آخر تغيير.
- [ ] `app_scope.dart`: `AppScope` (InheritedNotifier). `AppScope.of(context)` بيسمع للتغييرات، و`AppScope.read(context)` بيقرأ من غير ما يسمع.

### الخطوة 4: مكونات الواجهة (`lib/ui/`)

- [ ] `background.dart`: `AmbientBackground`، تدرج ثابت مع توهّجين ناعمين بيترسموا مرة واحدة جوه `RepaintBoundary`، من غير أنيميشن مستمر.
- [ ] `glass.dart`: `GlassSurface` (BackdropFilter blur + تعبئة `rgba(255,255,255,0.055)` + حد رفيع متدرج + خط إضاءة داخلي). فيه `GlassSurface.solid` من غير blur للقوايم، وتعطيل تلقائي للـ blur لو `reduceBlur` شغال.
- [ ] `neu.dart`
  - `NeuRaised` (سطح بارز) و`NeuInset` (سطح غاطس).
  - `NeuButton` (primary وsecondary) و`NeuIconButton`.
  - `NeuToggle`: مسار غاطس وزرار بارز مع توهّج أزرق.
  - `NeuField`: حقل إدخال غاطس مع validation.
  - `NeuSegmented`: اختيار أولوية.
- [ ] `island.dart`: نظام الـ Dynamic Island.
  - `IslandController`: `toast(title, icon, {action})` و`showContext(actions)` و`setLive(...)` و`clearLive()` و`expand()` و`collapse()` و`dismiss()`.
  - `IslandHost`: طبقة فوق الـ Navigator بتتركّب في `MaterialApp.builder`، فبتظهر فوق كل الشاشات والـ dialogs.
  - حركة الانتقال من compact لـ expanded بـ `SpringSimulation`، مع swipe لأعلى للإغلاق.
- [ ] `floating_nav.dart`: `FloatingNavBar` شريط زجاجي عايم بـ 4 تابات، ومؤشر نشط بيتحرك بـ spring مع توهّج أزرق خفيف.
- [ ] `components.dart`: `ScreenScaffold` و`SectionHeader` و`NovaChip` و`PriorityDot` و`TaskTile` و`StatTile` و`ProgressRing` و`Avatar` و`SettingsRow`.
- [ ] `charts.dart`: `WeekBarChart` بـ `CustomPainter`، 7 أعمدة مع خط الهدف اليومي.
- [ ] `states.dart`: `EmptyState` و`ErrorState` (مع Retry) و`SkeletonList` (shimmer بـ controller واحد بيتقفل أول ما التحميل يخلص).
- [ ] `overlays.dart`: `showNovaDialog` (dialog زجاجي) و`showNovaSheet` (bottom sheet يراعي الكيبورد وله drag handle).

### الخطوة 5: الشاشات (`lib/screens/`)

- [ ] `boot_screen.dart`: تحميل أولي (`store.init()`)، وخطأ مع Retry، وبعدها يوجّه لـ Auth أو Shell.
- [ ] `auth_screen.dart`: Login/Register بـ `AnimatedSwitcher`، validation، إظهار/إخفاء الباسورد، "Forgot password" كـ dialog.
- [ ] `shell_screen.dart`: `IndexedStack` لـ 4 تابات (Home وTasks وInsights وProfile) + `FloatingNavBar`.
- [ ] `home_screen.dart`: تحية، كارت التركيز، أول 3 مهام، إحصائيات سريعة، جرس الإشعارات.
- [ ] `tasks_screen.dart`: بحث، فلاتر (All/Open/Done/High)، تجميع حسب اليوم، swipe للحذف مع Undo في الـ Island، long-press لقايمة إجراءات.
- [ ] `task_detail_screen.dart`: تفاصيل المهمة، تعديل، حذف (dialog)، "Focus on this task".
- [ ] `task_editor_sheet.dart`: إضافة وتعديل مهمة (عنوان وملاحظات وأولوية وتاريخ).
- [ ] `focus_sheet.dart`: اختيار المدة (15/25/45/60) والمهمة المرتبطة.
- [ ] `insights_screen.dart`: رسم الأسبوع، حلقة الإنجاز، الـ streak، الهدف اليومي.
- [ ] `profile_screen.dart`: الاسم والإحصائيات وروابط الإعدادات والإشعارات وتسجيل الخروج.
- [ ] `settings_screen.dart`: toggles (Haptics وIsland وReduce blur وReduce motion)، الهدف اليومي، مسح البيانات.
- [ ] `notifications_screen.dart`: سجل الإشعارات، تعليم الكل كمقروء، مسح، حالة فارغة.

### الخطوة 6: نقطة الدخول والربط

- [ ] `main.dart`: ضبط edge-to-edge وقفل الوضع الرأسي، وبعدها `runApp(NovaApp())`.
- [ ] `app.dart`: بيخلق `AppStore` ويحطه في `AppScope`، وبيركّب `IslandHost` في `MaterialApp.builder`، والصفحة الرئيسية `BootScreen`.

**الربط بين الأجزاء:** `AppScope` يوصّل الـ `AppStore` لكل الشاشات. الـ `AppStore` عنده `IslandController` ويناديه بعد كل إجراء (إضافة مهمة، حذف، بدء تركيز). والـ `IslandHost` بيسمع للـ controller ويرسم الحالة.

### الخطوة 7: الاختبار والبناء

- [ ] `test/widget_test.dart`: smoke test بيتأكد إن التطبيق بيفتح.
- [x] `tool/patch_android.sh`: ضبط اسم التطبيق `Nova` بعد `flutter create`.
- [ ] `.github/workflows/build-apk.yml` (اتكتب ونتنشر، وهتتعلّم بعد ما أول تشغيل ينجح):
  checkout، Java 17، Flutter stable، تحميل Inter، `flutter create --platforms=android`، patch، `flutter pub get`، `flutter analyze`، `flutter test`، `flutter build apk --release`، رفع الـ APK كـ artifact وكـ GitHub Release.

### الخطوة 8: النشر والمتابعة

- [x] نشر الخطة دي (`docs/PLAN.md`) على الريبو.
- [ ] `commit` و`push` للكود على `main`.
- [ ] متابعة تشغيل الـ workflow من `gh api` وقراءة logs لو فشل.
- [ ] إصلاح أي errors وإعادة الدفع لحد ما البناء ينجح.
- [ ] تأكيد وجود الـ APK في صفحة Releases.

---

## 4. تنبيهات

- الـ APK موقّع بـ debug key، ولو عايز Play Store محتاج keystore خاص بيك.
- ممكن GitHub يرفض push ملف الـ workflow لو الـ token مالوش صلاحية `workflow`. لو حصل، الملف بيتضاف من الويب بنسخ ولصق.
- الـ Auth محلي فقط، ومفيش بيانات بتتبعت لأي سيرفر.

## 5. لو عايز تكمل يدوي

1. نفّذ `flutter create --platforms=android --org com.codesoli --project-name nova .` داخل المشروع مرة واحدة.
2. حمّل خطوط Inter (Regular وMedium وSemiBold وBold) في `assets/fonts/`.
3. شغّل `flutter pub get` وبعدها `flutter run`.
4. للـ APK: `flutter build apk --release`.
