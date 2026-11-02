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
├─ test/
│  ├─ widget_test.dart
│  ├─ store_test.dart
│  └─ formatters_test.dart
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

- [x] `tokens.dart`
  - `NovaColors`: `#080D19` و`#0D1525` و`#398BFF` و`#42C8FF` و`#F2F6FF` و`#8C9BB5` + ألوان حالات هادية.
  - `NovaSpace`: 4/8/12/16/20/24/32.
  - `NovaRadius`: sm/md/lg/xl/pill.
  - `NovaType`: سلم الخطوط (title وheadline وbody وcaption).
  - `NovaShadows`: raised وpressed.
- [x] `theme.dart`: `buildNovaTheme()` يرجّع `ThemeData` داكن بالخط والألوان وtransitions الصفحات.
- [x] `motion.dart`
  - `NovaSpring`: ثوابت الـ spring.
  - `NovaPageRoute`: انتقال fade + scale خفيف، ويحترم reduce motion.
  - `Pressable`: ويدجت بيصغّر 0.96 عند الضغط.
- [x] `ui_prefs.dart` (إضافة على الخطة): `UiPrefs` ويدجت بيوصّل إعدادات reduce blur وreduce motion للواجهة من غير ما كل الشاشات تتبني تاني.
- [x] `haptics.dart`: `Haptics.tap()` و`select()` و`success()`، وكلهم بيتأكدوا من إعداد الـ haptics.
- [x] `formatters.dart`: `formatTimer(Duration)` و`formatDue(DateTime)` و`greetingFor(DateTime)`.

### الخطوة 3: البيانات والحالة (`lib/data/`)

- [x] `models.dart`
  - `Priority` (low/medium/high).
  - `TaskItem`: id وtitle وnotes وpriority وdue وdone وcreatedAt وcompletedAt، مع `toJson` و`fromJson` و`copyWith`.
  - `FocusLog` و`NovaNotification` و`UserProfile` و`AppSettings`.
- [x] `storage.dart`: `Storage.read(key)` و`write(key, json)` فوق `shared_preferences`، مع fallback في الذاكرة لو فشل.
- [x] `app_store.dart`: `AppStore extends ChangeNotifier`، قلب التطبيق.
  - جلسة المستخدم: `init()` و`signIn()` و`signUp()` و`signOut()`.
  - المهام: `addTask()` و`updateTask()` و`toggleTask()` و`deleteTask()` و`undoDelete()`.
  - القراءة المشتقة: `todayTasks` و`openTasks` و`streak` و`focusMinutesLast7Days()`.
  - التركيز: `startFocus(minutes, taskId)` و`pauseFocus()` و`resumeFocus()` و`stopFocus()`. فيه `Timer.periodic` كل ثانية، وبيشتغل **بس** وقت الجلسة.
  - الإشعارات: `pushNotification()` و`markAllRead()` و`clearNotifications()`.
  - الإعدادات: `setHaptics()` و`setIsland()` و`setReduceBlur()` و`setReduceMotion()` و`setDailyGoal()`.
  - الحفظ: `_persist()` بتحفظ بعد 300 ملي ثانية من آخر تغيير.
- [x] `app_scope.dart`: `AppScope` (InheritedNotifier). `AppScope.of(context)` بيسمع للتغييرات، و`AppScope.read(context)` بيقرأ من غير ما يسمع.

### الخطوة 4: مكونات الواجهة (`lib/ui/`)

- [x] `background.dart`: `AmbientBackground`، تدرج ثابت مع توهّجين ناعمين بيترسموا مرة واحدة جوه `RepaintBoundary`، من غير أنيميشن مستمر.
- [x] `glass.dart`: `GlassSurface` (BackdropFilter blur + تعبئة `rgba(255,255,255,0.055)` + حد رفيع متدرج + خط إضاءة داخلي). فيه `GlassSurface.solid` من غير blur للقوايم، وتعطيل تلقائي للـ blur لو `reduceBlur` شغال.
- [x] `neu.dart`
  - `NeuRaised` (سطح بارز) و`NeuInset` (سطح غاطس).
  - `NeuButton` (primary وsecondary) و`NeuIconButton`.
  - `NeuToggle`: مسار غاطس وزرار بارز مع توهّج أزرق.
  - `NeuField`: حقل إدخال غاطس مع validation.
  - `NeuSegmented`: اختيار أولوية.
- [x] `island.dart`: نظام الـ Dynamic Island.
  - `IslandController`: `toast(title, icon, {action})` و`showContext(actions)` و`setLive(...)` و`clearLive()` و`expand()` و`collapse()` و`dismiss()`.
  - `IslandHost`: طبقة فوق الـ Navigator بتتركّب في `MaterialApp.builder`، فبتظهر فوق كل الشاشات والـ dialogs.
  - حركة الانتقال من compact لـ expanded بـ `SpringSimulation`، مع swipe لأعلى للإغلاق.
- [x] `floating_nav.dart`: `FloatingNavBar` شريط زجاجي عايم بـ 4 تابات، ومؤشر نشط بيتحرك بـ spring مع توهّج أزرق خفيف.
- [x] `components.dart`: `ScreenScaffold` و`SectionHeader` و`NovaChip` و`PriorityDot` و`TaskTile` و`StatTile` و`ProgressRing` و`Avatar` و`SettingsRow`.
- [x] `charts.dart`: `WeekBarChart` بـ `CustomPainter`، 7 أعمدة مع خط الهدف اليومي.
- [x] `states.dart`: `EmptyState` و`ErrorState` (مع Retry) و`SkeletonList` (shimmer بـ controller واحد بيتقفل أول ما التحميل يخلص).
- [x] `overlays.dart`: `showNovaDialog` (dialog زجاجي) و`showNovaSheet` (bottom sheet يراعي الكيبورد وله drag handle).

### الخطوة 5: الشاشات (`lib/screens/`)

- [x] `boot_screen.dart`: تحميل أولي (`store.init()`)، وخطأ مع Retry، وبعدها يوجّه لـ Auth أو Shell.
- [x] `auth_screen.dart`: Login/Register بـ `AnimatedSwitcher`، validation، إظهار/إخفاء الباسورد، "Forgot password" كـ dialog.
- [x] `shell_screen.dart`: `IndexedStack` لـ 4 تابات (Home وTasks وInsights وProfile) + `FloatingNavBar`.
- [x] `home_screen.dart`: تحية، كارت التركيز، أول 3 مهام، إحصائيات سريعة، جرس الإشعارات.
- [x] `tasks_screen.dart`: بحث، فلاتر (All/Open/Done/High)، تجميع حسب اليوم، swipe للحذف مع Undo في الـ Island، long-press لقايمة إجراءات.
- [x] `task_detail_screen.dart`: تفاصيل المهمة، تعديل، حذف (dialog)، "Focus on this task".
- [x] `task_editor_sheet.dart`: إضافة وتعديل مهمة (عنوان وملاحظات وأولوية وتاريخ).
- [x] `focus_sheet.dart`: اختيار المدة (15/25/45/60) والمهمة المرتبطة.
- [x] `insights_screen.dart`: رسم الأسبوع، حلقة الإنجاز، الـ streak، الهدف اليومي.
- [x] `profile_screen.dart`: الاسم والإحصائيات وروابط الإعدادات والإشعارات وتسجيل الخروج.
- [x] `settings_screen.dart`: toggles (Haptics وIsland وReduce blur وReduce motion)، الهدف اليومي، مسح البيانات.
- [x] `notifications_screen.dart`: سجل الإشعارات، تعليم الكل كمقروء، مسح، حالة فارغة.

### الخطوة 6: نقطة الدخول والربط

- [x] `main.dart`: ضبط edge-to-edge وقفل الوضع الرأسي، وبعدها `runApp(NovaApp())`.
- [x] `app.dart`: بيخلق `AppStore` ويحطه في `AppScope`، وبيركّب `IslandHost` في `MaterialApp.builder`، والصفحة الرئيسية `BootScreen`.

**الربط بين الأجزاء:** `AppScope` يوصّل الـ `AppStore` لكل الشاشات. الـ `AppStore` عنده `IslandController` ويناديه بعد كل إجراء (إضافة مهمة، حذف، بدء تركيز). والـ `IslandHost` بيسمع للـ controller ويرسم الحالة.

### الخطوة 7: الاختبار والبناء

- [x] `test/widget_test.dart`: اختبارات واجهة (شاشة الدخول، إنشاء حساب ووصول للـ Home، رسائل التحقق).
- [x] `test/store_test.dart` (إضافة): اختبارات المهام والتركيز والحفظ والإعدادات والـ JSON.
- [x] `test/formatters_test.dart` (إضافة): اختبارات التنسيق.
- [x] `tool/patch_android.sh`: ضبط اسم التطبيق `Nova` بعد `flutter create`.
- [x] `.github/workflows/build-apk.yml` (اتجرّب وشغال: البناء نجح والـ APK التجريبي اتنشر في Releases):
  checkout، Java 17، Flutter stable، تحميل Inter، `flutter create --platforms=android`، patch، `flutter pub get`، `flutter analyze`، `flutter test`، `flutter build apk --release`، رفع الـ APK كـ artifact وكـ GitHub Release.

### الخطوة 8: النشر والمتابعة

- [x] تأكيد أن آخر commit على `main` هو `b3ad2c1` وأن ملفات التطبيق والاختبارات والـ workflow مرفوعة.
- [x] تشغيل GitHub Actions رقم `4` (`Build Android APK`)؛ جميع الخطوات نجحت، بما فيها `Analyze` و`Test` و`Build release APK` و`Publish GitHub Release`.
- [x] معالجة مشكلة layout: صفوف `CrossAxisAlignment.stretch` داخل scroll views كانت بتستقبل ارتفاعاً غير محدود؛ اتصلحت باستخدام `IntrinsicHeight` في الشاشات المتأثرة، والاختبارات بعدها نجحت.
- [x] نشر Release `build-4` وفيه `nova.apk`.

- [x] نشر الخطة دي (`docs/PLAN.md`) على الريبو.
- [x] `commit` و`push` للكود على `main`؛ الكود موجود على الفرع `main` ضمن آخر commit `b3ad2c1`.
- [x] متابعة تشغيل الـ workflow وقراءة حالة الـ job والخطوات؛ آخر تشغيل `#4` اكتمل بنجاح.
- [x] إصلاح أخطاء الـ analyzer ومشكلة layout ظهرت في اختبارات الواجهة، ثم إعادة البناء بنجاح.
- [x] تأكيد نشر `nova.apk` داخل Release باسم `build-4` (حجم الملف 52,215,675 بايت).

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

---

## 6. المرحلة الجديدة: Android System-wide Dynamic Island

**الهدف:** نقل الـ Island من طبقة Flutter داخل التطبيق فقط إلى نافذة Android عائمة تعمل بعد مغادرة Nova، مع استقبال أحداث النظام التي يسمح بها Android وبموافقة المستخدم.

### 6.1 البنية Native Android

- [x] إضافة tool/android-src/MainActivity.kt لربط Flutter بـ Android عبر MethodChannel باسم com.codesoli.nova/system_island.
- [x] إضافة SystemIslandBridge في lib/platform/system_island_bridge.dart لقراءة الصلاحيات وبدء/إيقاف الخدمة.
- [x] إضافة NovaIslandService.kt كـ Foreground Service يستخدم WindowManager وTYPE_APPLICATION_OVERLAY لعرض الكبسولة خارج التطبيق.
- [x] إضافة NovaNotificationListener.kt لاستقبال الإشعارات التي يسمح المستخدم للتطبيق بقراءتها وإرسال عنوانها ونصها المتاح للـ Island.
- [x] تحديث tool/patch_android.sh لنسخ ملفات Kotlin إلى مشروع Android الذي يولّده Flutter، وإضافة الصلاحيات وتعريف الخدمات إلى Manifest.
- [x] إضافة لوحة إعدادات داخل Settings لفتح إعدادات Overlay وNotification Access، وفحص حالة الإذنين، وبدء/إيقاف الخدمة.
- [ ] التحقق من تجميع Kotlin وManifest على GitHub Actions وإصلاح أي أخطاء بناء.
- [ ] اختبار منح/سحب الصلاحيات، إعادة تشغيل الجهاز، إيقاف الخدمة، وسلوك Android 8–15 على أجهزة فعلية.

### 6.2 أنواع الأحداث — حالة التنفيذ

- [x] إشعارات التطبيقات: استقبال onNotificationPosted وعرض العنوان والنص المتاحين.
- [ ] تجاهل إشعارات Nova الداخلية والتجميع ومنع التكرار والتحكم في مدة ظهور كل حدث.
- [ ] إعدادات الخصوصية: إخفاء معاينة المحتوى، قائمة تطبيقات مسموح بها، واستثناء تطبيقات حساسة.
- [ ] الموسيقى: قراءة MediaSession metadata وعرض اسم الفنان/المقطع، ثم توفير أزرار تشغيل/إيقاف/التالي عبر جلسة الوسائط.
- [ ] الشحن والبطارية: استقبال ACTION_BATTERY_CHANGED وتحديث الحالة.
- [ ] سماعات الرأس: رصد تغيّر اتصال AudioDevice مع دعم قيود إصدارات Android.
- [ ] المكالمات: إظهار حالة الرنين/المكالمة فقط عبر API وصلاحيات الهاتف المسموح بها، من دون جمع أو عرض رقم المتصل افتراضياً.
- [ ] Wi-Fi وBluetooth والشبكة: عرض الحالات التي توفرها واجهات النظام العامة؛ لا يُفترض توفر SSID أو تفاصيل الشبكة على كل إصدار.
- [ ] التنزيلات والرفع: دعم التنزيلات التي يعلن عنها النظام أو التطبيقات عبر إشعاراتها؛ لا توجد واجهة عامة تتيح مراقبة كل عمليات الرفع والتنزيل لكل التطبيقات.
- [ ] الملاحة: عرض بيانات الملاحة فقط عندما يوفر تطبيق الملاحة إشعاراً أو تكاملاً مصرحاً به.

### 6.3 قيود Android والخصوصية

- إذن SYSTEM_ALERT_WINDOW خاص ويمنحه المستخدم يدوياً من إعدادات النظام.
- إذن Notification Access واسع وحساس؛ يجب شرح الغرض بوضوح، وعدم تخزين نصوص الإشعارات أو إرسالها إلى أي خادم.
- بعض أحداث الهاتف والوسائط والشبكة مقيدة بإصدار Android أو صلاحيات إضافية أو واجهة يتيحها التطبيق المصدر.
- لا يمكن ضمان التقاط «كل شيء» حرفياً، ولا يمكن قراءة محتوى شاشة كل تطبيق أو تجاوز قيود النظام.
- يجب أن تبقى الخدمة قابلة للإيقاف من Nova ومن إشعار Foreground Service، وألا تعمل قبل موافقة المستخدم.

### 6.4 معايير القبول قبل اعتبار الميزة مكتملة

- [ ] ظهور الكبسولة فوق تطبيق آخر وبعد الرجوع للشاشة الرئيسية.
- [ ] استقبال إشعار تجريبي من تطبيق آخر وعرضه مرة واحدة من دون تسريب محتوى عند تفعيل وضع الخصوصية.
- [ ] عمل Start/Stop بشكل موثوق، وعدم بقاء نافذة يتيمة بعد إيقاف الخدمة.
- [ ] معالجة رفض الصلاحيات وسحبها أثناء التشغيل من دون crash.
- [ ] اختبار الأداء واستهلاك البطارية والذاكرة، وعدم استخدام polling سريع أو أنيميشن مستمر غير ضروري.
- [ ] اختبارات على أكثر من إصدار Android ومقاسات شاشات وفتحات كاميرا مختلفة.
- [ ] توثيق القيود الفعلية لكل نوع حدث قبل وضع علامة [x].

**ملاحظة الحالة الحالية:** تم بناء الأساس Native والربط ولوحة الصلاحيات فقط. لا تعتبر الموسيقى أو البطارية أو المكالمات أو باقي الأحداث منفذة حتى تضاف وتُختبر فعلياً.
### 6.5 استكمال أحداث النظام والوسائط والسماعات

**تنبيه حالة:** العلامات التالية تعني أن مسار الكود أُضيف إلى الريبو؛ لا تعني اجتياز بناء Android أو اختبار أجهزة فعلية قبل نجاح CI والاختبار اليدوي.

- [x] الموسيقى: ربط MediaSessionManager بالجلسات النشطة، قراءة اسم المقطع والفنان وحالة التشغيل/الإيقاف، تحديث الجلسات عند وصول إشعار/اتصال Notification Listener.
- [x] تحكم أولي بالوسائط من الكبسولة: الضغط للتبديل Play/Pause، والضغط المطوّل لإرسال Next إلى الجلسة النشطة.
- [x] البطارية والشحن: استقبال ACTION_BATTERY_CHANGED وعرض نسبة بطارية الهاتف وحالة الشحن عند تغيرها.
- [x] السماعات السلكية واللاسلكية: AudioDeviceCallback وACTION_HEADSET_PLUG وBluetooth ACL لاكتشاف الاتصال والفصل ونوع جهاز الصوت.
- [x] بطارية Bluetooth: قراءة مستوى البطارية إذا أرسله Android في broadcast المدعوم؛ لا يتم استدعاء hidden/non-SDK APIs.
- [x] بطارية السماعات المنفصلة: تحليل إشعارات تطبيقات الشركات الداعمة لاستخراج L/R/Case عند وجود النسب في نص الإشعار، مع دعم النسبة العامة عند توفرها.
- [ ] ضمان نسب منفصلة لكل سماعة وعلبة الشحن على كل العلامات التجارية؛ Android لا يوفّر API عاماً موحداً لهذه البيانات، وبعض الشركات لا تكشفها إلا داخل تطبيقها أو عبر إشعار.
- [x] المكالمات: TelephonyCallback على Android 12+ وPhoneStateListener للإصدارات الأقدم، مع إظهار الرنين/المكالمة/الانتهاء فقط ودون قراءة رقم المتصل.
- [x] الشبكة: ConnectivityManager default network callback لتصنيف Offline وWi-Fi وMobile data وEthernet.
- [x] الملاحة: تمييز إشعارات Navigation category وتطبيقات الخرائط المعروفة وعرض نص الإرشادات الذي يسمح الإشعار بقراءته.
- [ ] مراقبة كل عمليات الرفع والتنزيل لكل التطبيقات؛ غير متاحة بواجهة Android عامة، ويقتصر الدعم الحالي على الإشعارات التي تنشرها التطبيقات.
- [x] إضافة أذونات ACCESS_NETWORK_STATE وBLUETOOTH_CONNECT وREAD_PHONE_STATE وطلب الأذونات الخطرة اختيارياً عند بدء الخدمة.
- [x] جعل رفض إذن الهاتف لا يمنع تشغيل بقية ميزات Island؛ أحداث المكالمات تتوقف فقط عند رفض الإذن.
- [x] توضيح دعم بطارية السماعات وحدوده في لوحة إعدادات Nova.

### 6.6 اختبارات مطلوبة قبل اعتماد الإكمال

- [ ] GitHub Actions: نجاح flutter analyze وflutter test وAndroid release APK بعد إضافة Kotlin.
- [ ] اختبار MediaSession مع أكثر من تطبيق موسيقى، والتحقق من Play/Pause/Next.
- [ ] اختبار الهاتف على الشاحن وعند فصل الشاحن، ومقارنة النسبة مع إعدادات Android.
- [ ] اختبار سماعة Bluetooth وسماعة سلكية، وسماعات TWS من شركات مختلفة، وتسجيل ما إذا كانت L/R/Case تظهر أو لا.
- [ ] اختبار المكالمات بعد منح READ_PHONE_STATE وبعد رفضه.
- [ ] اختبار Wi-Fi وبيانات الهاتف وفصل الشبكة وإعادة الاتصال.
- [ ] اختبار إشعارات Google Maps وWaze مع إخفاء محتوى الإشعارات.
- [ ] قياس استهلاك CPU/RAM والبطارية أثناء الخمول ولمدة تشغيل طويلة.

**قيد مهم لبطارية السماعات:** يمكن لـ Nova إظهار نسب اليسار/اليمين/العلبة فقط إذا أرسلها Android أو ظهرت في إشعار تطبيق الشركة. لا يوجد مسار مضمون لقراءة كل هذه النسب من كل سماعة، ولن تعرض Nova أرقاماً تقديرية أو مختلقة.